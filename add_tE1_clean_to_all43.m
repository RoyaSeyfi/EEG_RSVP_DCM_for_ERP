%% add_tE1_clean_to_all43.m
% Creates a subject-specific tE1_clean vector and appends it to each
% artefact-marked aMspmeeg*.mat file under the root directory.

clearvars;
clc;

%% Settings
rootDir = 'E:\Subjects44\SPM_MAT_DAT';
expectedSubjects = 43;
expectedChannels = 63;
analysisWindowSeconds = [0 0.5];   % 0-500 ms
makeHeaderBackup = true;

%% Initialise SPM
spm('defaults', 'eeg');

%% Find all 43 artefact-marked datasets
fileList = dir(fullfile(rootDir, '**', 'aMspmeeg*.mat'));
keepFile = false(numel(fileList), 1);
for fileNumber = 1:numel(fileList)
    if ~fileList(fileNumber).isdir
        keepFile(fileNumber) = true;
    end
end
fileList = fileList(keepFile);

if ~(numel(fileList) == expectedSubjects)
    error('Expected %d aMspmeeg*.mat files, but found %d.', ...
        expectedSubjects, numel(fileList));
end


% Sort by the final number found in the subject folder name.
subjectNumber = nan(numel(fileList), 1);
for fileNumber = 1:numel(fileList)
    [~, subjectFolderName] = fileparts(fileList(fileNumber).folder);
    numberText = regexp(subjectFolderName, '\d+', 'match');
    if ~isempty(numberText)
        subjectNumber(fileNumber) = str2double(numberText{end});
    end
end

sortableNumber = subjectNumber;
sortableNumber(isnan(sortableNumber)) = Inf;
[~, sortingOrder] = sort(sortableNumber);
fileList = fileList(sortingOrder);
subjectNumber = subjectNumber(sortingOrder);

%% Log variables
logSubject = strings(expectedSubjects, 1);
logFile = strings(expectedSubjects, 1);
logE1Count = nan(expectedSubjects, 1);
logStatus = strings(expectedSubjects, 1);
logMessage = strings(expectedSubjects, 1);

fprintf('\nFound %d aMspmeeg datasets.\n', numel(fileList));

%% Process every subject
for fileNumber = 1:numel(fileList)
    matFile = fullfile(fileList(fileNumber).folder, fileList(fileNumber).name);
    datFile = fullfile(fileList(fileNumber).folder, ...
        [fileList(fileNumber).name(1:end-4) '.dat']);

    if isnan(subjectNumber(fileNumber))
        subjectLabel = string(fileList(fileNumber).folder);
    else
        subjectLabel = "sub" + string(subjectNumber(fileNumber));
    end

    logSubject(fileNumber) = subjectLabel;
    logFile(fileNumber) = string(matFile);

    fprintf('\n[%d/%d] %s\n', fileNumber, numel(fileList), subjectLabel);
    fprintf('File: %s\n', matFile);

    try
        if ~isfile(datFile)
            error('The paired DAT file is missing.');
        end


        eegData = spm_eeg_load(matFile);
        if ~(eegData.nchannels == expectedChannels)
            error('Expected %d channels, but found %d.', ...
                expectedChannels, eegData.nchannels);
        end

        if ~(eegData.ntrials == 1)
            error('One continuous trial was expected before convolution.');
        end


        %% Read events
        try
            eventList = events(eegData, 1);
        catch
            eventList = events(eegData);
        end

        if isempty(eventList)
            error('No events were found.');
        end


        numberOfEvents = numel(eventList);
        eventTimes = nan(numberOfEvents, 1);
        eventTypes = strings(numberOfEvents, 1);
        eventValues = strings(numberOfEvents, 1);

        for eventNumber = 1:numberOfEvents
            eventTimes(eventNumber) = ...
                readEventNumber(eventList(eventNumber), 'time');
            eventTypes(eventNumber) = ...
                readEventText(eventList(eventNumber), 'type');
            eventValues(eventNumber) = ...
                readEventText(eventList(eventNumber), 'value');
        end

        normalType = lower(regexprep(strtrim(eventTypes), '[\s_\-]', ''));
        normalValue = lower(regexprep(strtrim(eventValues), '[\s_\-]', ''));

        isBoundary = false(numberOfEvents, 1);
        isE1 = false(numberOfEvents, 1);
        for eventNumber = 1:numberOfEvents
            if contains(normalType(eventNumber), 'boundary') || ...
                contains(normalValue(eventNumber), 'boundary')
                isBoundary(eventNumber) = true;
            end
            if normalType(eventNumber) == "e1" || normalValue(eventNumber) == "e1"
                if ~isBoundary(eventNumber)
                    isE1(eventNumber) = true;
                end
            end
        end

        allE1Times = sort(eventTimes(isE1 & isfinite(eventTimes)));
        boundaryTimes = sort(eventTimes(isBoundary & isfinite(eventTimes)));
        if isempty(allE1Times)
            error('No E1 events were found.');
        end


        %% Remove E1 events whose 0-500 ms window is invalid
        % Check the response window of each E1 separately.
        cleanOnsets = zeros(numel(allE1Times), 1);
        numberOfCleanEvents = 0;
        firstValidTime = eegData.time(1);
        lastValidTime = eegData.time(end);

        for onsetNumber = 1:numel(allE1Times)
            responseStart = allE1Times(onsetNumber) + analysisWindowSeconds(1);
            responseEnd = allE1Times(onsetNumber) + analysisWindowSeconds(2);
            keepThisEvent = true;

            if responseStart < firstValidTime || responseEnd > lastValidTime
                keepThisEvent = false;
            end

            for boundaryNumber = 1:numel(boundaryTimes)
                if responseStart <= boundaryTimes(boundaryNumber) && ...
                    responseEnd >= boundaryTimes(boundaryNumber)
                    keepThisEvent = false;
                end
            end

            if keepThisEvent
                numberOfCleanEvents = numberOfCleanEvents + 1;
                cleanOnsets(numberOfCleanEvents) = allE1Times(onsetNumber);
            end
        end

        tE1_clean = double(cleanOnsets(1:numberOfCleanEvents));
        tE1_clean = tE1_clean(:);

        if isempty(tE1_clean)
            error('No usable E1 events remained after range/boundary checks.');
        end

        if ~all(diff(tE1_clean) > 0)
            error('Clean E1 onsets contain duplicates or are not increasing.');
        end


        %% Create one recoverable backup of the original MAT header
        if makeHeaderBackup
            backupFile = [matFile '.before_tE1_clean.bak'];
            if ~isfile(backupFile)
                copyfile(matFile, backupFile);
            end
        end

        %% Append tE1_clean to this subject's SPM MAT file
        save(matFile, 'tE1_clean', '-append');

        savedVariable = whos('-file', matFile, 'tE1_clean');
        if isempty(savedVariable)
            error('tE1_clean could not be verified inside the MAT file.');
        end

        if ~isequal(savedVariable.size, size(tE1_clean))
            error('Saved tE1_clean has an unexpected size.');
        end


        logE1Count(fileNumber) = numel(tE1_clean);
        logStatus(fileNumber) = "PASS";
        logMessage(fileNumber) = "tE1_clean appended and verified.";

        fprintf('PASS: tE1_clean saved | %d onsets\n', numel(tE1_clean));

    catch errorInformation
        logStatus(fileNumber) = "ERROR";
        logMessage(fileNumber) = string(errorInformation.message);
        fprintf(2, 'ERROR: %s\n', errorInformation.message);
    end

    clear eegData tE1_clean eventList eventTimes eventTypes eventValues;
end

%% Save log
resultTable = table(logSubject, logFile, logE1Count, logStatus, logMessage, ...
    'VariableNames', {'Subject', 'MatFile', 'CleanE1Count', ...
    'Status', 'Message'});

timeStamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
logPath = fullfile(rootDir, ['tE1_clean_log_' timeStamp '.csv']);
writetable(resultTable, logPath);

fprintf('\n========== FINISHED ==========\n');
fprintf('PASS: %d\n', sum(resultTable.Status == "PASS"));
fprintf('ERROR: %d\n', sum(resultTable.Status == "ERROR"));
fprintf('Log: %s\n', logPath);


%% Helper functions
function textValue = readEventText(oneEvent, fieldName)
    textValue = "";

    if ~isfield(oneEvent, fieldName) || isempty(oneEvent.(fieldName))
        return;
    end

    fieldValue = oneEvent.(fieldName);
    if iscell(fieldValue)
        fieldValue = fieldValue{1};
    end
    if isempty(fieldValue)
        return;
    end

    if ischar(fieldValue)
        textValue = string(fieldValue);
    else
        textValue = strjoin(string(fieldValue(:)), " ");
    end
end


function numberValue = readEventNumber(oneEvent, fieldName)
    numberValue = NaN;

    if ~isfield(oneEvent, fieldName) || isempty(oneEvent.(fieldName))
        return;
    end

    fieldValue = oneEvent.(fieldName);
    if iscell(fieldValue)
        fieldValue = fieldValue{1};
    end

    if isnumeric(fieldValue) && ~isempty(fieldValue)
        numberValue = double(fieldValue(1));
    end
end
