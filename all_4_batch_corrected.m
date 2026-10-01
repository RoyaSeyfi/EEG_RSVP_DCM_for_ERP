%% all_4_batch_corrected.m
% Run the verified SPM25 Batch 1 for all 43 subjects.
% The selected *_job.m file must contain, in this order:
%   1) Convolution modelling
%   2) Prepare
%   3) Convert2Images
%   4) Smooth

clearvars;
clc;

%% Settings
rootDir = 'E:\Subjects44\SPM_MAT_DAT';
expectedSubjects = 43;
expectedChannels = 63;
skipExistingConvolutionOutput = true;

%% Initialise SPM
spm('defaults', 'eeg');
spm_jobman('initcfg');

%% Select the verified Batch 1 *_job.m file
[jobName, jobFolder] = uigetfile( ...
    {'*_job.m', 'SPM Batch job (*_job.m)'}, ...
    'Select the verified Batch 1 _job.m file');

if isequal(jobName, 0)
    error('No Batch 1 job file was selected.');
end


jobPath = fullfile(jobFolder, jobName);

clear matlabbatch
run(jobPath);

if ~(exist('matlabbatch', 'var') == 1)
    error('The selected _job.m file did not create matlabbatch.');
end


templateBatch = matlabbatch;
clear matlabbatch

fprintf('Selected Batch: %s\n', jobPath);

%% Find and validate all four modules
convIndex = [];
prepareIndex = [];
convertIndex = [];
smoothIndex = [];

for moduleNumber = 1:numel(templateBatch)
    oneModule = templateBatch{moduleNumber};

    if isfield(oneModule, 'spm')
        if isfield(oneModule.spm, 'meeg')
            if isfield(oneModule.spm.meeg, 'modelling') && ...
                isfield(oneModule.spm.meeg.modelling, 'convmodel')
                convIndex(end + 1) = moduleNumber; %#ok<SAGROW>
            end

            if isfield(oneModule.spm.meeg, 'preproc') && ...
                isfield(oneModule.spm.meeg.preproc, 'prepare')
                prepareIndex(end + 1) = moduleNumber; %#ok<SAGROW>
            end

            if isfield(oneModule.spm.meeg, 'images') && ...
                isfield(oneModule.spm.meeg.images, 'convert2images')
                convertIndex(end + 1) = moduleNumber; %#ok<SAGROW>
            end
        end

        if isfield(oneModule.spm, 'spatial') && ...
            isfield(oneModule.spm.spatial, 'smooth')
            smoothIndex(end + 1) = moduleNumber; %#ok<SAGROW>
        end
    end
end

if ~isscalar(convIndex)
    error('The selected job must contain exactly one Convolution modelling module.');
end

if ~isscalar(prepareIndex)
    error('The selected job must contain exactly one Prepare module.');
end

if ~isscalar(convertIndex)
    error('The selected job must contain exactly one Convert2Images module.');
end

if ~isscalar(smoothIndex)
    error('The selected job must contain exactly one Smooth module.');
end

if ~(convIndex < prepareIndex && prepareIndex < convertIndex && ...
    convertIndex < smoothIndex)
    error(['The modules must be ordered as: Convolution modelling, Prepare, ' ...
        'Convert2Images, Smooth.']);
end


convTemplate = templateBatch{convIndex}.spm.meeg.modelling.convmodel;

if ~(numel(convTemplate.sess.cond) == 1)
    error('Exactly one condition (all_images) was expected.');
end

if ~strcmpi(strtrim(convTemplate.sess.cond(1).name), 'all_images')
    error('The condition name in Batch 1 must be all_images.');
end

if ~(isfield(convTemplate.sess.cond(1), 'define') && ...
    isfield(convTemplate.sess.cond(1).define, 'manual'))
    error('Condition events must be defined manually.');
end

if ~(isfield(convTemplate, 'timing') && ...
    isfield(convTemplate.timing, 'timewin') && ...
    numel(convTemplate.timing.timewin) == 2)
    error('The Convolution modelling time window is missing or invalid.');
end


% SPM stores this time window in milliseconds. Use the actual Batch value
% for boundary/range checks (for this project it should be [-200 500] ms).
analysisWindowSeconds = double(convTemplate.timing.timewin(:)') / 1000;

fprintf('Convolution time window: [%g %g] ms\n', ...
    convTemplate.timing.timewin(1), convTemplate.timing.timewin(2));

%% Force Prepare to contain the two required operations
% The input-file dependency already stored in the job is preserved.
setTypeTask = struct;
setTypeTask.settype.channels = {struct('all', 'all')};
setTypeTask.settype.newtype = 'EEG';

projectTask = struct;
projectTask.project3dEEG = 1;

templateBatch{prepareIndex}.spm.meeg.preproc.prepare.task = ...
    {setTypeTask, projectTask};

fprintf(['Prepare confirmed: Set channel type (All -> EEG) + ' ...
    'Project EEG sensors to 2D.\n']);

%% Find the 43 input datasets automatically
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


% Sort by the last number in each subject-folder name.
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

%% Prepare the progress log
timeStamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
logFile = fullfile(rootDir, ['Batch1_log_' timeStamp '.csv']);

logSubject = strings(expectedSubjects, 1);
logInput = strings(expectedSubjects, 1);
logE1Count = nan(expectedSubjects, 1);
logStatus = strings(expectedSubjects, 1);
logMessage = strings(expectedSubjects, 1);

fprintf('\nFound %d input datasets.\n', numel(fileList));
fprintf('Progress log: %s\n\n', logFile);

%% Run the complete four-module Batch for every subject
for fileNumber = 1:numel(fileList)
    inputFile = fullfile(fileList(fileNumber).folder, ...
        fileList(fileNumber).name);
    pairedDat = fullfile(fileList(fileNumber).folder, ...
        [fileList(fileNumber).name(1:end-4) '.dat']);

    if isnan(subjectNumber(fileNumber))
        subjectLabel = string(fileList(fileNumber).folder);
    else
        subjectLabel = "sub" + string(subjectNumber(fileNumber));
    end

    logSubject(fileNumber) = subjectLabel;
    logInput(fileNumber) = string(inputFile);

    fprintf('\n[%d/%d] %s\n', ...
        fileNumber, numel(fileList), subjectLabel);
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


        tE1_clean = makeCleanE1(eegData, analysisWindowSeconds);
        logE1Count(fileNumber) = numel(tE1_clean);

        currentBatch = templateBatch;
        currentConv = currentBatch{convIndex}.spm.meeg.modelling.convmodel;
        currentConv.sess.D = {inputFile};
        currentConv.sess.cond(1).define.manual.onset = tE1_clean;
        currentConv.sess.cond(1).define.manual.duration = 0;
        currentBatch{convIndex}.spm.meeg.modelling.convmodel = currentConv;

        convPrefix = char(string(currentConv.prefix));
        expectedConvOutput = fullfile(fileList(fileNumber).folder, ...
            [convPrefix fileList(fileNumber).name]);

        if skipExistingConvolutionOutput && isfile(expectedConvOutput)
            logStatus(fileNumber) = "SKIPPED";
            logMessage(fileNumber) = ...
                "The convolution output already exists; no overwrite was attempted.";
            fprintf('SKIPPED: output already exists: %s\n', ...
                expectedConvOutput);
        else
            spm_jobman('run', currentBatch);
            logStatus(fileNumber) = "PASS";
            logMessage(fileNumber) = "All four Batch 1 modules completed.";
            fprintf('PASS: %s | clean E1 = %d\n', ...
                subjectLabel, numel(tE1_clean));
        end

    catch errorInformation
        logStatus(fileNumber) = "ERROR";
        logMessage(fileNumber) = string(errorInformation.message);
        fprintf(2, 'ERROR: %s\n', errorInformation.message);
    end

    progressTable = table( ...
        logSubject(1:fileNumber), ...
        logInput(1:fileNumber), ...
        logE1Count(1:fileNumber), ...
        logStatus(1:fileNumber), ...
        logMessage(1:fileNumber), ...
        'VariableNames', {'Subject', 'InputFile', 'CleanE1Count', ...
        'Status', 'Message'});
    writetable(progressTable, logFile);

    clear eegData currentBatch currentConv tE1_clean;
end

%% Final report
finalTable = readtable(logFile, 'TextType', 'string');
fprintf('\n========== BATCH 1 FINISHED ==========\n');
fprintf('PASS: %d\n', sum(finalTable.Status == "PASS"));
fprintf('SKIPPED: %d\n', sum(finalTable.Status == "SKIPPED"));
fprintf('ERROR: %d\n', sum(finalTable.Status == "ERROR"));
fprintf('Log file: %s\n', logFile);


%% Local functions
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
