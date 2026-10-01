%% run_convolution_all43.m
% Runs a saved SPM25 Convolution modelling batch for all 43 subjects.
% The saved batch must contain exactly ONE module: Convolution modelling.
% It may be saved as either *_job.m or *.mat.

clearvars;
clc;

%% Settings
rootDir = 'E:\Subjects44\SPM_MAT_DAT';
expectedSubjects = 43;
expectedChannels = 63;
analysisWindowSeconds = [0 0.5];   % corresponds to [0 500] ms
skipExistingOutput = true;

%% Initialise SPM
spm('defaults', 'eeg');
spm_jobman('initcfg');

%% Select the saved Convolution-only batch
[jobName, jobFolder] = uigetfile( ...
    {'*.m;*.mat', 'SPM batch job (*.m, *.mat)'}, ...
    'Select the Convolution-only batch job');
if isequal(jobName, 0)
    error('No batch job was selected.');
end


jobPath = fullfile(jobFolder, jobName);
templateBatch = loadBatchJob(jobPath);
fprintf('Selected batch: %s\n', jobPath);

%% Find the single Convolution modelling module
convIndex = [];
for moduleNumber = 1:numel(templateBatch)
    oneModule = templateBatch{moduleNumber};
    if isfield(oneModule, 'spm') && ...
        isfield(oneModule.spm, 'meeg') && ...
        isfield(oneModule.spm.meeg, 'modelling') && ...
        isfield(oneModule.spm.meeg.modelling, 'convmodel')
        convIndex(end+1) = moduleNumber; %#ok<SAGROW>
    end
end

if ~(isscalar(convIndex) && numel(templateBatch) == 1)
    error(['The selected batch must contain only one module: Convolution ' ...
        'modelling. Remove Prepare, Convert2Images, and Smooth.']);
end


convTemplate = templateBatch{convIndex}.spm.meeg.modelling.convmodel;
if ~(isfield(convTemplate, 'sess') && ...
    isfield(convTemplate.sess, 'cond') && ...
    numel(convTemplate.sess.cond) == 1)
    error('The Convolution batch must contain exactly one condition.');
end

if ~strcmpi(strtrim(convTemplate.sess.cond(1).name), 'all_images')
    error('The condition name must be all_images.');
end

if ~(isfield(convTemplate.sess.cond(1), 'define') && ...
    isfield(convTemplate.sess.cond(1).define, 'manual'))
    error('Set How to define events to Specify manually in the saved batch.');
end


%% Find the 43 input datasets
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


% Sort using the last number in the subject folder name.
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

%% Progress log
timeStamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
logFile = fullfile(rootDir, ['Convolution_log_' timeStamp '.csv']);

logSubject = strings(expectedSubjects, 1);
logInput = strings(expectedSubjects, 1);
logE1Count = nan(expectedSubjects, 1);
logStatus = strings(expectedSubjects, 1);
logMessage = strings(expectedSubjects, 1);

fprintf('\nFound %d input datasets.\n', numel(fileList));
fprintf('Progress log: %s\n', logFile);

%% Run the saved batch once for each subject
for fileNumber = 1:numel(fileList)
    inputFile = fullfile(fileList(fileNumber).folder, fileList(fileNumber).name);
    pairedDat = fullfile(fileList(fileNumber).folder, ...
        [fileList(fileNumber).name(1:end-4) '.dat']);

    if isnan(subjectNumber(fileNumber))
        subjectLabel = string(fileList(fileNumber).folder);
    else
        subjectLabel = "sub" + string(subjectNumber(fileNumber));
    end

    logSubject(fileNumber) = subjectLabel;
    logInput(fileNumber) = string(inputFile);

    fprintf('\n[%d/%d] %s\n', fileNumber, numel(fileList), subjectLabel);
    fprintf('Input: %s\n', inputFile);

    try
        if ~isfile(pairedDat)
            error('The paired DAT file is missing.');
        end


        eegData = spm_eeg_load(inputFile);
        if ~(eegData.nchannels == expectedChannels)
            error('Expected %d channels, but found %d.', ...
                expectedChannels, eegData.nchannels);
        end

        if ~(eegData.ntrials == 1)
            error('One continuous trial was expected before convolution.');
        end


        % Create this subject's own clean E1 onset vector.
        tE1_clean = makeCleanE1(eegData, analysisWindowSeconds);
        logE1Count(fileNumber) = numel(tE1_clean);

        % Make a fresh copy of the saved batch for this subject.
        currentBatch = templateBatch;
        currentConv = currentBatch{convIndex}.spm.meeg.modelling.convmodel;

        % Fully specify the Convolution model. This removes any unresolved
        % or accidentally cleared inputs from the saved GUI template.
        channelSelection = struct;
        channelSelection.type = 'EEG';
        currentConv.channels = {channelSelection};
        currentConv.timing.timewin = [0 500];
        currentConv.timing.units = 'secs';
        currentConv.timing.utime = 1;

        currentConv.sess.cond(1).name = 'all_images';
        currentConv.sess.D = {inputFile};
        currentConv.sess.cond(1).define.manual.onset = tE1_clean;
        currentConv.sess.cond(1).define.manual.duration = 0;
        currentConv.sess.cond(1).tmod = 0;
        currentConv.sess.cond(1).pmod = ...
            struct('name', {}, 'param', {}, 'poly', {});
        currentConv.sess.cond(1).orth = 0;

        currentConv.sess.multi = {''};
        currentConv.sess.convregress = struct('name', {}, 'val', {});
        currentConv.sess.multi_conv_reg = {''};
        currentConv.sess.regress = struct('name', {}, 'val', {});
        currentConv.sess.multi_reg = {''};
        currentConv.sess.savereg = false;
        currentConv.sess.hpf = 10;

        currentConv.bases = struct;
        currentConv.bases.fourier.order = 12;
        currentConv.volt = 1;
        currentConv.prefix = 'C';

        currentBatch{convIndex}.spm.meeg.modelling.convmodel = currentConv;

        convPrefix = currentConv.prefix;
        if iscell(convPrefix)
            convPrefix = convPrefix{1};
        end
        convPrefix = char(string(convPrefix));

        expectedMat = fullfile(fileList(fileNumber).folder, ...
            [convPrefix fileList(fileNumber).name]);
        expectedDat = fullfile(fileList(fileNumber).folder, ...
            [convPrefix fileList(fileNumber).name(1:end-4) '.dat']);

        if skipExistingOutput && isfile(expectedMat) && isfile(expectedDat)
            logStatus(fileNumber) = "SKIPPED";
            logMessage(fileNumber) = "Complete convolution output already exists.";
            fprintf('SKIPPED: complete output already exists.\n');
        else
            spm_jobman('run', currentBatch);
            if ~(isfile(expectedMat) && isfile(expectedDat))
                error('SPM finished without creating the expected MAT/DAT output pair.');
            end


            logStatus(fileNumber) = "PASS";
            logMessage(fileNumber) = "Convolution modelling completed.";
            fprintf('PASS: clean E1 = %d\n', numel(tE1_clean));
        end

    catch errorInformation
        logStatus(fileNumber) = "ERROR";
        logMessage(fileNumber) = string(errorInformation.message);
        fprintf(2, 'ERROR: %s\n', errorInformation.message);
    end

    progressTable = table(logSubject(1:fileNumber), ...
        logInput(1:fileNumber), logE1Count(1:fileNumber), ...
        logStatus(1:fileNumber), logMessage(1:fileNumber), ...
        'VariableNames', {'Subject', 'InputFile', 'CleanE1Count', ...
        'Status', 'Message'});
    writetable(progressTable, logFile);

    clear eegData currentBatch currentConv tE1_clean;
end

%% Final report
fprintf('\n========== CONVOLUTION FINISHED ==========\n');
fprintf('PASS: %d\n', sum(logStatus == "PASS"));
fprintf('SKIPPED: %d\n', sum(logStatus == "SKIPPED"));
fprintf('ERROR: %d\n', sum(logStatus == "ERROR"));
fprintf('Log file: %s\n', logFile);


%% Local functions
function matlabbatch = loadBatchJob(jobPath)
    [~, ~, extension] = fileparts(jobPath);

    switch lower(extension)
    case '.mat'
        savedJob = load(jobPath);
        if ~isfield(savedJob, 'matlabbatch')
            error('The selected MAT file does not contain matlabbatch.');
        end

        matlabbatch = savedJob.matlabbatch;

    case '.m'
        matlabbatch = {};
        run(jobPath);
        if ~(iscell(matlabbatch) && ~isempty(matlabbatch))
            error('The selected M file did not create a nonempty matlabbatch.');
        end


    otherwise
        error('Select an SPM batch saved as *_job.m or *.mat.');
    end
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
