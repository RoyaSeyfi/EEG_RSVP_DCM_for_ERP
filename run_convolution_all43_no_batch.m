%% run_convolution_all43_no_batch.m
% Self-contained SPM25 Convolution GLM for all 43 subjects.
% No saved Batch file and no Batch Editor are required.

clearvars;
clc;

%% Study settings
rootDir = 'E:\Subjects44\SPM_MAT_DAT';
expectedSubjects = 43;
expectedChannels = 63;
timeWindowMs = [0 500];
analysisWindowSeconds = timeWindowMs / 1000;
conditionName = 'all_images';
fourierOrder = 12;
highPassSeconds = 10;
outputPrefix = 'C';
skipExistingOutput = true;

%% Initialise SPM25
spm('defaults', 'eeg');
spm_jobman('initcfg');

%% Find the 43 artefact-marked input datasets
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


% Sort using the number in each subject folder.
subjectNumber = nan(numel(fileList), 1);
for fileNumber = 1:numel(fileList)
    [~, folderName] = fileparts(fileList(fileNumber).folder);
    numberText = regexp(folderName, '\d+', 'match');
    if ~isempty(numberText)
        subjectNumber(fileNumber) = str2double(numberText{end});
    end
end

sortNumber = subjectNumber;
sortNumber(isnan(sortNumber)) = Inf;
[~, order] = sort(sortNumber);
fileList = fileList(order);
subjectNumber = subjectNumber(order);

%% Create progress log
timeStamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
logFile = fullfile(rootDir, ['Batch1_Convolution_log_' timeStamp '.csv']);

logSubject = strings(expectedSubjects, 1);
logInput = strings(expectedSubjects, 1);
logOutput = strings(expectedSubjects, 1);
logE1Count = nan(expectedSubjects, 1);
logStatus = strings(expectedSubjects, 1);
logMessage = strings(expectedSubjects, 1);

fprintf('\nFound %d subjects.\n', numel(fileList));
fprintf('Input pattern: aMspmeeg*.mat\n');
fprintf('Time window: [%d %d] ms\n', timeWindowMs);
fprintf('Log: %s\n', logFile);

%% Process every subject
for fileNumber = 1:numel(fileList)
    inputFile = fullfile(fileList(fileNumber).folder, fileList(fileNumber).name);
    inputDat = fullfile(fileList(fileNumber).folder, ...
        [fileList(fileNumber).name(1:end-4) '.dat']);
    outputFile = fullfile(fileList(fileNumber).folder, ...
        [outputPrefix fileList(fileNumber).name]);

    if isnan(subjectNumber(fileNumber))
        subjectLabel = "file" + string(fileNumber);
    else
        subjectLabel = "sub" + string(subjectNumber(fileNumber));
    end

    logSubject(fileNumber) = subjectLabel;
    logInput(fileNumber) = string(inputFile);
    logOutput(fileNumber) = string(outputFile);

    fprintf('\n========================================\n');
    fprintf('[%d/%d] %s\n', fileNumber, numel(fileList), subjectLabel);
    fprintf('Input: %s\n', inputFile);

    try
        if ~isfile(inputDat)
            error('The paired input DAT file is missing.');
        end


        inputEEG = spm_eeg_load(inputFile);
        if ~(inputEEG.nchannels == expectedChannels)
            error('Expected %d channels, but found %d.', ...
                expectedChannels, inputEEG.nchannels);
        end

        if ~(inputEEG.ntrials == 1)
            error('One continuous trial was expected before convolution.');
        end


        inputCoordinates = inputEEG.coor2D;
        if isempty(inputCoordinates)
            error('The input dataset has no 2D channel coordinates.');
        end


        tE1_clean = makeCleanE1(inputEEG, analysisWindowSeconds);
        logE1Count(fileNumber) = numel(tE1_clean);
        fprintf('Clean E1 events: %d\n', numel(tE1_clean));

        if skipExistingOutput && isfile(outputFile)
        % Do not recalculate an existing GLM, but make sure its EEG
        % channel types and 2D coordinates are restored correctly.
            outputEEG = restoreSensors(outputFile, inputCoordinates, expectedChannels);
            logStatus(fileNumber) = "SKIPPED_EXISTING";
            logMessage(fileNumber) = ...
                "Existing convolution output retained; sensors restored.";
            fprintf('Existing output retained and sensors restored.\n');
        else
        %% Build this subject's Convolution modelling job
            convmodel = struct;
            convmodel.channels{1}.type = 'EEG';
            convmodel.timing.timewin = timeWindowMs;
            convmodel.timing.units = 'secs';
            convmodel.timing.utime = 1;

            convmodel.sess.D = {inputFile};
            convmodel.sess.cond(1).name = conditionName;
            convmodel.sess.cond(1).define.manual.onset = tE1_clean;
            convmodel.sess.cond(1).define.manual.duration = 0;
            convmodel.sess.cond(1).tmod = 0;
            convmodel.sess.cond(1).pmod = ...
                struct('name', {}, 'param', {}, 'poly', {});
            convmodel.sess.cond(1).orth = 0;

            convmodel.sess.multi = {''};
            convmodel.sess.convregress = struct('name', {}, 'val', {});
            convmodel.sess.multi_conv_reg = {''};
            convmodel.sess.regress = struct('name', {}, 'val', {});
            convmodel.sess.multi_reg = {''};
            convmodel.sess.savereg = 0;
            convmodel.sess.hpf = highPassSeconds;

            convmodel.bases.fourier.order = fourierOrder;
            convmodel.volt = 1;
            convmodel.prefix = outputPrefix;

            matlabbatch = {};
            matlabbatch{1}.spm.meeg.modelling.convmodel = convmodel;
            spm_jobman('run', matlabbatch);

            if ~isfile(outputFile)
                error('SPM finished, but the expected C-prefixed MAT file was not found.');
            end


            %% Restore EEG channel type and 2D coordinates
            outputEEG = restoreSensors(outputFile, inputCoordinates, expectedChannels);

            logStatus(fileNumber) = "PASS";
            logMessage(fileNumber) = "Convolution GLM completed; sensors restored.";
            fprintf('PASS: %s\n', outputFile);
        end

    catch errorInformation
        logStatus(fileNumber) = "ERROR";
        logMessage(fileNumber) = string(errorInformation.message);
        fprintf(2, 'ERROR: %s\n', errorInformation.message);
    end

    progressTable = table( ...
        logSubject(1:fileNumber), ...
        logInput(1:fileNumber), ...
        logOutput(1:fileNumber), ...
        logE1Count(1:fileNumber), ...
        logStatus(1:fileNumber), ...
        logMessage(1:fileNumber), ...
        'VariableNames', {'Subject', 'InputFile', 'OutputFile', ...
        'CleanE1Count', 'Status', 'Message'});
    writetable(progressTable, logFile);

    clear inputEEG outputEEG inputCoordinates tE1_clean convmodel matlabbatch;
end

%% Final report
finalTable = readtable(logFile, 'TextType', 'string');
fprintf('\n========== FINAL RESULT ==========\n');
fprintf('PASS: %d\n', sum(finalTable.Status == "PASS"));
fprintf('SKIPPED EXISTING: %d\n', ...
    sum(finalTable.Status == "SKIPPED_EXISTING"));
fprintf('ERROR: %d\n', sum(finalTable.Status == "ERROR"));
fprintf('Log file: %s\n', logFile);


%% Local functions
function outputEEG = restoreSensors(outputFile, inputCoordinates, expectedChannels)
    outputEEG = spm_eeg_load(outputFile);
    if ~(outputEEG.nchannels == expectedChannels)
        error('The convolution output does not contain the expected number of channels.');
    end


    outputEEG = coor2D(outputEEG, 1:expectedChannels, inputCoordinates);
    outputEEG = chantype(outputEEG, ':', 'EEG');
    save(outputEEG);
end


function tE1_clean = makeCleanE1(eegData, analysisWindowSeconds)
    try
        eventList = events(eegData, 1);
    catch
        eventList = events(eegData);
    end

    if isempty(eventList)
        error('No events were found in the dataset.');
    end


    numberOfEvents = numel(eventList);
    eventTimes = nan(numberOfEvents, 1);
    eventTypes = strings(numberOfEvents, 1);
    eventValues = strings(numberOfEvents, 1);

    for eventNumber = 1:numberOfEvents
        eventTimes(eventNumber) = readEventNumber(eventList(eventNumber), 'time');
        eventTypes(eventNumber) = readEventText(eventList(eventNumber), 'type');
        eventValues(eventNumber) = readEventText(eventList(eventNumber), 'value');
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
        error('No usable E1 events remained after boundary/range checks.');
    end

    if ~all(diff(tE1_clean) > 0)
        error('The clean E1 onsets contain duplicates or are not increasing.');
    end

end


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
