%% make_convolution_glm_results_report.m
% Publication-style Results report for Roya's convolution GLM.
%
% Study design implemented here
% -----------------------------
% - 43 participants: 20 monolingual, 23 bilingual
% - one deconvolved condition: all_images
% - 63 EEG channels
% - response window: 0-500 ms
% - Fourier order 12 (25 basis functions)
%
% Main outputs
% ------------
% 1. Figure_1_group_responses_and_differences.png/.pdf/.fig
%       Group mean +/- SEM and Monolingual - Bilingual difference +/- 95% CI
%       for three pre-specified posterior sensor clusters.
% 2. Figure_2_group_blind_scalp_maps.png/.pdf/.fig
%       Scalp maps at latencies selected from the equal-weight grand mean,
%       not from the group contrast.
% 3. Convolution_GLM_Results_Tables.docx
%       Word-ready model-QC, descriptive-window, and topography tables.
% 4. Supplementary subject/time-point/QC data retained in the MAT archive.
% 5. A supplementary design R2 heatmap.
% 6. Results_reporting_guide_FA.txt
%       A Persian guide stating what belongs in the Results chapter.
%
% IMPORTANT
% ---------
% This script deliberately does NOT run another group significance test.
% The confirmatory inference is the already specified SPM scalp-by-time
% two-sample analysis, which controls multiplicity over the search volume.
% SEM overlap and the descriptive window table are not significance tests.

clearvars;
clc;
close all;
commandwindow;

%% =========================== SETTINGS ================================

% Change only these paths if needed.
study.spmFolder = 'C:\Users\Roya\Documents\MATLAB\spm_25.01.02';
study.rootFolder = 'E:\Subjects44\SPM_MAT_DAT';

% The final convolution files produced by run_convolution_all43.m should
% normally start with CaMspmeeg. If your exact prefix differs, edit this.
study.filePattern = 'CaMspmeeg*.mat';
study.condition = 'all_images';
study.outputFolder = fullfile(study.rootFolder, ...
    'Convolution_GLM_Results_Report');

% FAST RETRY MODE
% The full analysis has already completed and saved its MAT archive. Keep
% this true now to create only the missing DOCX without loading 43 datasets
% again. Change it to false whenever you want to rebuild the entire report.
study.wordOnlyFromSavedResults = true;

% Final groups after exclusion of subject 17.
study.monolingualIDs = [2 3 4 5 9 11 12 13 16 19 21 22 25 30 31 32 34 35 38 47];
study.bilingualIDs = [1 7 8 10 14 20 24 26 27 28 29 33 36 37 39 40 41 42 43 44 45 46 48];

study.expectedSubjects = 43;
study.expectedChannels = 63;
study.expectedBasisFunctions = 25;
study.analysisWindowMs = [0 500];

% Sensor clusters are descriptive sensor-space summaries. They must not be
% presented as source-localised cortical regions.
study.clusterNames = { ...
    'Medial occipital'; ...
    'Lateral occipital'; ...
    'Occipitotemporal'};

study.clusterChannels = { ...
    {'POz','O1','Oz','O2'}; ...
    {'PO7','PO3','PO4','PO8'}; ...
    {'TP7','P7','P8','TP8'}};

% Fixed descriptive windows. If these windows were not defined before the
% group comparison was inspected, describe them as exploratory/descriptive,
% not preregistered or confirmatory. The labels are deliberately neutral;
% do not rename them P1/N1/N250 unless waveform polarity and scalp
% distribution justify that interpretation.
study.windowNames = { ...
    'Early_70_130_ms'; ...
    'Middle_130_220_ms'; ...
    'Late_220_300_ms'; ...
    'Late_extended_300_450_ms'};
study.windowsMs = [70 130; 130 220; 220 300; 300 450];

% Three broad, non-overlapping windows used only to choose group-blind GFP
% peaks for scalp visualisation. The equal-weight grand mean gives the two
% groups equal influence despite unequal sample sizes.
study.topographyWindowNames = {'Early','Middle','Late'};
study.topographySearchWindowsMs = [70 130; 130 220; 220 400];
study.topographyAverageHalfWidthMs = 15;

study.monolingualColor = [0.00 0.45 0.74];
study.bilingualColor = [0.85 0.33 0.10];
study.differenceColor = [0.20 0.20 0.20];

%% ======================== INITIAL CHECKS =============================

if ~(numel(study.monolingualIDs) == 20)
    error('The monolingual list must contain 20 subjects.');
end

if ~(numel(study.bilingualIDs) == 23)
    error('The bilingual list must contain 23 subjects.');
end

if ~isempty(intersect(study.monolingualIDs, study.bilingualIDs))
    error('A subject appears in both groups.');
end

if ~(numel([study.monolingualIDs study.bilingualIDs]) == ...
    study.expectedSubjects)
    error('The two groups must contain 43 subjects.');
end

if ~isfolder(study.spmFolder)
    error('SPM folder was not found: %s', study.spmFolder);
end

if ~isfolder(study.rootFolder)
    error('Root data folder was not found: %s', study.rootFolder);
end


if study.wordOnlyFromSavedResults
    if ~isfolder(study.outputFolder)
        error(['Word-only mode requires the completed results folder: %s. ' ...
            'Set study.wordOnlyFromSavedResults to false for a full run.'], ...
            study.outputFolder);
    end

    tableFolder = fullfile(study.outputFolder,'Tables');
    if ~isfolder(tableFolder)
        mkdir(tableFolder);
    end

    savedResultsFile = fullfile(study.outputFolder, ...
        'convolution_glm_results_data.mat');
    if ~isfile(savedResultsFile)
        error(['Saved results were not found: %s. Set ' ...
            'study.wordOnlyFromSavedResults to false for a full run.'], ...
            savedResultsFile);
    end


    cached = load(savedResultsFile,'modelQCSummary','windowTable', ...
        'topographyPeakTable');
    requiredFields = {'modelQCSummary','windowTable','topographyPeakTable'};
    if ~all(isfield(cached,requiredFields))
        error('The saved MAT file does not contain all tables required for DOCX.');
    end


    if height(cached.windowTable) > 0 && ...
        ismember('AmplitudeUnit', ...
        cached.windowTable.Properties.VariableNames)
        amplitudeUnit = char(string(cached.windowTable.AmplitudeUnit(1)));
    else
        amplitudeUnit = 'native unit';
    end

    wordTableFile = fullfile(tableFolder, ...
        'Convolution_GLM_Results_Tables.docx');
    wordDocumentCreated = writeWordResultsDocument(wordTableFile,study, ...
        cached.modelQCSummary,cached.windowTable, ...
        cached.topographyPeakTable,amplitudeUnit);

    if wordDocumentCreated
        fprintf('\nDOCX RESULTS TABLES CREATED SUCCESSFULLY\n%s\n', ...
            wordTableFile);
    else
        error(['The DOCX was not created. Read the immediately preceding ' ...
            'warning for the exact DOCX packaging error.']);
    end
    return;
end

addpath(study.spmFolder);
spm('defaults','eeg');

if ~isfolder(study.outputFolder)
    mkdir(study.outputFolder);
end

figureFolder = fullfile(study.outputFolder,'Figures');
tableFolder = fullfile(study.outputFolder,'Tables');
if ~isfolder(figureFolder)
    mkdir(figureFolder);
end
if ~isfolder(tableFolder)
    mkdir(tableFolder);
end

subjectIDs = [study.monolingualIDs study.bilingualIDs];
groupCode = [ones(1,numel(study.monolingualIDs)), ...
    2*ones(1,numel(study.bilingualIDs))];
groupName = strings(study.expectedSubjects,1);
groupName(groupCode == 1) = "Monolingual";
groupName(groupCode == 2) = "Bilingual";

fprintf('\nSearching for final convolution datasets...\n');
datasetMap = findConvolutionDatasets(study, subjectIDs);

%% =========================== LOAD DATA ===============================

numberOfSubjects = numel(subjectIDs);
numberOfClusters = numel(study.clusterNames);

allSensorResponses = [];
allClusterResponses = [];
timeMs = [];
referenceLabels = {};
referenceCoordinates = [];
amplitudeLabel = 'Amplitude';
amplitudeUnit = 'native unit';

datasetFile = strings(numberOfSubjects,1);
conditionTrials = nan(numberOfSubjects,1);
channelCount = nan(numberOfSubjects,1);
timePointCount = nan(numberOfSubjects,1);
timeStartMs = nan(numberOfSubjects,1);
timeEndMs = nan(numberOfSubjects,1);
samplingIntervalMs = nan(numberOfSubjects,1);
unitFound = strings(numberOfSubjects,1);

for subjectIndex = 1:numberOfSubjects
    subjectID = subjectIDs(subjectIndex);
    currentFile = datasetMap{subjectIndex};
    datasetFile(subjectIndex) = string(currentFile);

    fprintf('[%02d/%02d] Loading subject %02d\n', ...
        subjectIndex, numberOfSubjects, subjectID);

    eegData = spm_eeg_load(currentFile);
    conditionList = cellstr(eegData.condlist);
    conditionPosition = find(strcmpi(conditionList,study.condition),1);
    if isempty(conditionPosition)
        error('Condition %s is missing for subject %02d.', ...
            study.condition, subjectID);
    end


    exactCondition = conditionList{conditionPosition};
    trialIndex = eegData.indtrial(exactCondition);
    if isempty(trialIndex)
        error('Condition %s has no trial for subject %02d.', ...
            study.condition, subjectID);
    end


    currentTimeMs = double(eegData.time(:)') * 1000;
    eegIndex = getEEGIndices(eegData);
    currentLabels = cellstr(eegData.chanlabels(eegIndex));

    if ~(numel(eegIndex) == study.expectedChannels)
        error('Subject %02d has %d EEG channels; expected %d.', ...
            subjectID, numel(eegIndex), study.expectedChannels);
    end

    if ~(currentTimeMs(1) <= study.analysisWindowMs(1)+1 && ...
        currentTimeMs(end) >= study.analysisWindowMs(2)-1)
        error('Subject %02d does not cover the expected 0-500 ms window.', ...
            subjectID);
    end


    if subjectIndex == 1
        timeMs = currentTimeMs;
        referenceLabels = currentLabels;
        referenceCoordinates = get2DCoordinates(eegData,eegIndex);
        allSensorResponses = nan(numberOfSubjects, ...
            study.expectedChannels,numel(timeMs));
        allClusterResponses = nan(numberOfSubjects, ...
            numberOfClusters,numel(timeMs));
    else
        if ~(numel(currentTimeMs) == numel(timeMs) && ...
            max(abs(currentTimeMs-timeMs)) < 0.01)
            error('Time vector differs for subject %02d.',subjectID);
        end

    end

    reorderIndex = eegData.indchannel(referenceLabels);
    if ~(numel(reorderIndex) == study.expectedChannels && ...
        all(isfinite(reorderIndex)))
        error('Channel labels/order cannot be matched for subject %02d.', ...
            subjectID);
    end


    currentData = double(eegData(reorderIndex,:,trialIndex));
    currentData = mean(currentData,3,'omitnan');

    [scaleToMicrovolts,currentUnit,unitIsKnown] = ...
        getMicrovoltScale(eegData,reorderIndex);
    unitFound(subjectIndex) = string(currentUnit);
    currentData = currentData .* scaleToMicrovolts;

    if subjectIndex == 1
        if unitIsKnown
            amplitudeLabel = 'Estimated response amplitude (microvolts)';
            amplitudeUnit = 'microvolts';
        else
            amplitudeLabel = sprintf('Estimated response amplitude (%s)', ...
                currentUnit);
            amplitudeUnit = currentUnit;
        end
    end

    allSensorResponses(subjectIndex,:,:) = currentData;

    for clusterIndex = 1:numberOfClusters
        wantedLabels = study.clusterChannels{clusterIndex};
        [present,location] = ismember(lower(string(wantedLabels)), ...
            lower(string(referenceLabels)));
        if ~all(present)
            error('Required cluster channels are missing for subject %02d.', ...
                subjectID);
        end

        allClusterResponses(subjectIndex,clusterIndex,:) = ...
            mean(currentData(location,:),1,'omitnan');
    end

    conditionTrials(subjectIndex) = numel(trialIndex);
    channelCount(subjectIndex) = numel(eegIndex);
    timePointCount(subjectIndex) = numel(currentTimeMs);
    timeStartMs(subjectIndex) = currentTimeMs(1);
    timeEndMs(subjectIndex) = currentTimeMs(end);
    if numel(currentTimeMs) > 1
        samplingIntervalMs(subjectIndex) = median(diff(currentTimeMs));
    end

    clear eegData currentData;
end

%% ===================== EVENT COUNTS AND MODEL QC =====================

cleanE1Count = readLatestEventCounts(study.rootFolder,subjectIDs);

rankValue = nan(numberOfSubjects,1);
maximumOffDiagonalR2 = nan(numberOfSubjects,1);
medianOffDiagonalR2 = nan(numberOfSubjects,1);
standardizedConditionNumber = nan(numberOfSubjects,1);
sumR2 = zeros(study.expectedBasisFunctions);
numberOfUsableDesigns = 0;

for subjectIndex = 1:numberOfSubjects
    [rankValue(subjectIndex),maximumOffDiagonalR2(subjectIndex), ...
        medianOffDiagonalR2(subjectIndex), ...
        standardizedConditionNumber(subjectIndex),oneR2] = ...
        inspectSubjectDesign(datasetMap{subjectIndex}, ...
        study.expectedBasisFunctions,study.condition);

    if ~isempty(oneR2)
        sumR2 = sumR2 + oneR2;
        numberOfUsableDesigns = numberOfUsableDesigns + 1;
    end
end

subjectQCTable = table(subjectIDs(:),groupName,datasetFile, ...
    cleanE1Count,conditionTrials,channelCount,timePointCount, ...
    timeStartMs,timeEndMs,samplingIntervalMs,unitFound,rankValue, ...
    maximumOffDiagonalR2,medianOffDiagonalR2, ...
    standardizedConditionNumber, ...
    'VariableNames',{'SubjectID','Group','DatasetFile','CleanE1Count', ...
    'ConditionTrials','EEGChannels','TimePoints','TimeStartMs','TimeEndMs', ...
    'SamplingIntervalMs','OriginalUnit','DesignRank', ...
    'MaximumOffDiagonalR2','MedianOffDiagonalR2', ...
    'StandardizedConditionNumber'});

modelQCSummary = makeModelQCSummary(subjectQCTable,study, ...
    numberOfUsableDesigns);

if numberOfUsableDesigns > 0
    groupMeanR2 = sumR2 ./ numberOfUsableDesigns;
    makeDesignHeatmap(groupMeanR2,study,figureFolder);
else
    groupMeanR2 = [];
    warning('No usable subject-level SPM design matrices were found.');
end

%% ======================= DESCRIPTIVE TABLES =========================

[windowTable,subjectWindowTable] = makeWindowTables( ...
    allClusterResponses,timeMs,subjectIDs,groupCode,study,amplitudeUnit);

timePointTable = makeTimePointTable(allClusterResponses,timeMs, ...
    groupCode,study,amplitudeUnit);

%% ========================= MAIN FIGURE ===============================

makeWaveformFigure(allClusterResponses,timeMs,groupCode,study, ...
    amplitudeLabel,figureFolder);

%% ======================== SCALP MAPS ================================

[topographyPeakTable,topographyData] = makeTopographyFigure( ...
    allSensorResponses,timeMs,groupCode,referenceCoordinates, ...
    study,amplitudeUnit,figureFolder);

%% ====================== SAVE REUSABLE DATA ===========================

wordTableFile = fullfile(tableFolder, ...
    'Convolution_GLM_Results_Tables.docx');

save(fullfile(study.outputFolder,'convolution_glm_results_data.mat'), ...
    'study','subjectIDs','groupCode','groupName','timeMs', ...
    'referenceLabels','referenceCoordinates','allSensorResponses', ...
    'allClusterResponses','subjectQCTable','modelQCSummary', ...
    'windowTable','subjectWindowTable','timePointTable', ...
    'topographyPeakTable','topographyData','groupMeanR2', ...
    'wordTableFile','-v7.3');

wordDocumentCreated = writeWordResultsDocument(wordTableFile,study, ...
    modelQCSummary,windowTable,topographyPeakTable,amplitudeUnit);

writeReportingGuide(fullfile(study.outputFolder, ...
    'Results_reporting_guide_FA.txt'),study,modelQCSummary, ...
    topographyPeakTable,amplitudeUnit);

fprintf('\n============================================================\n');
fprintf('CONVOLUTION GLM RESULTS REPORT COMPLETED\n');
fprintf('Output folder:\n%s\n',study.outputFolder);
fprintf('Main figure: Figure_1_group_responses_and_differences\n');
fprintf('Scalp figure: Figure_2_group_blind_scalp_maps\n');
if wordDocumentCreated
    fprintf('Word tables: %s\n',wordTableFile);
else
    fprintf(['Word tables were not created. See the preceding warning ' ...
        'for the exact DOCX packaging error.\n']);
end
fprintf(['No group p-values were calculated by this script. Use the ' ...
    'SPM scalp-by-time analysis for confirmatory group inference.\n']);
fprintf('============================================================\n');

try
    beep;
catch
end

%% =========================== FUNCTIONS ===============================

function datasetMap = findConvolutionDatasets(study,subjectIDs)
    files = dir(fullfile(study.rootFolder,'**',study.filePattern));
    files = files(~[files.isdir]);

    if isempty(files)
        error(['No files matched %s below %s. Edit study.filePattern at ' ...
            'the top of the script.'],study.filePattern,study.rootFolder);
    end

    datasetMap = cell(numel(subjectIDs),1);
    filesWithoutDat = strings(0,1);
    filesWithoutRecognisedID = strings(0,1);

    for i = 1:numel(files)
        fullName = fullfile(files(i).folder,files(i).name);

        % The subject identifier may be in either the filename (for example,
        % CaMspmeeg_asub013_...) or a parent folder (sub013, subject13, or 13).
        id = extractSubjectID(fullName,study.rootFolder,subjectIDs);
        if ~isfinite(id)
            filesWithoutRecognisedID(end+1,1) = string(fullName); %#ok<AGROW>
            continue;
        end

        position = find(subjectIDs == id,1);
        if isempty(position)
            continue;
        end

        % An SPM M/EEG dataset requires both the MAT header and DAT data file.
        [folderName,baseName] = fileparts(fullName);
        datFile = fullfile(folderName,[baseName '.dat']);
        if ~isfile(datFile)
            filesWithoutDat(end+1,1) = string(fullName); %#ok<AGROW>
            continue;
        end

        if ~isempty(datasetMap{position})
            error(['More than one %s file was found for subject %02d:\n%s\n%s\n' ...
                'Make study.filePattern more specific.'], ...
                study.filePattern,id,datasetMap{position},fullName);
        end
        datasetMap{position} = fullName;
    end

    missingDataset = false(size(datasetMap));
    for subjectIndex = 1:numel(datasetMap)
        if isempty(datasetMap{subjectIndex})
            missingDataset(subjectIndex) = true;
        end
    end
    missing = subjectIDs(missingDataset);
    if ~isempty(missing)
        fprintf('\n============================================================\n');
        fprintf('CONVOLUTION DATASET SEARCH FAILED\n');
        fprintf('MAT files matching %s: %d\n',study.filePattern,numel(files));
        fprintf('Missing final subject IDs: %s\n', ...
            char(strjoin(string(missing),', ')));

        if ~isempty(filesWithoutDat)
            fprintf('\nMatching MAT files without their paired DAT file:\n');
            for fileIndex = 1:numel(filesWithoutDat)
                fprintf('  %s\n',char(filesWithoutDat(fileIndex)));
            end
        end

        if ~isempty(filesWithoutRecognisedID)
            fprintf('\nFiles whose subject ID could not be recognised:\n');
            numberToDisplay = min(10,numel(filesWithoutRecognisedID));
            for fileIndex = 1:numberToDisplay
                fprintf('  %s\n', ...
                    char(filesWithoutRecognisedID(fileIndex)));
            end
            if numel(filesWithoutRecognisedID) > numberToDisplay
                fprintf('  ... plus %d additional file(s).\n', ...
                    numel(filesWithoutRecognisedID)-numberToDisplay);
            end
        end
        fprintf('============================================================\n\n');

        error(['No usable final convolution dataset was found for ' ...
            'subject(s): %s. See the diagnostic list printed above.'], ...
            char(strjoin(string(missing),', ')));
    end
end


function id = extractSubjectID(filePath,rootFolder,allowedSubjectIDs)
    id = NaN;

    [currentFolder,baseName] = fileparts(filePath);

    % First inspect the filename. This recognises strings such as asub013,
    % sub-013, subject_13, and participant13 anywhere in the basename.
    token = regexp(baseName, ...
        '(?i)(?:participant|subject|sub)[-_ ]*0*(\d+)(?!\d)', ...
        'tokens','once');
    if ~isempty(token)
        id = str2double(token{1});
        return;
    end

    % Next inspect only folders below study.rootFolder. Excluding rootFolder is
    % important when the root itself has a name such as Subjects44.
    normalisedRoot = removeTrailingFileSeparator(char(string(rootFolder)));
    currentFolder = removeTrailingFileSeparator(currentFolder);

    while ~strcmpi(currentFolder,normalisedRoot)
        [parentFolder,leafFolder] = fileparts(currentFolder);
        if isempty(leafFolder) || strcmpi(parentFolder,currentFolder)
            break;
        end

        token = regexp(leafFolder, ...
            '(?i)^(?:(?:participant|subject|sub)[-_ ]*)?0*(\d+)$', ...
            'tokens','once');
        if ~isempty(token)
            id = str2double(token{1});
            return;
        end

        currentFolder = removeTrailingFileSeparator(parentFolder);
    end

    % Final conservative fallback for names such as CaMspmeeg_013. A number is
    % accepted only when exactly one delimited 1- or 2-digit token corresponds
    % to one of the final subject IDs. Ambiguous filenames remain unassigned.
    numberTokens = regexp(baseName,'(?<!\d)0*(\d{1,2})(?!\d)', ...
        'tokens');
    candidateIDs = nan(numel(numberTokens),1);
    for tokenIndex = 1:numel(numberTokens)
        candidateIDs(tokenIndex) = str2double(numberTokens{tokenIndex}{1});
    end
    candidateIDs = unique(candidateIDs(isfinite(candidateIDs)),'stable');
    candidateIDs = candidateIDs(ismember(candidateIDs,allowedSubjectIDs));
    if numel(candidateIDs) == 1
        id = candidateIDs;
    end
end


function pathText = removeTrailingFileSeparator(pathText)
    pathText = char(string(pathText));
    while numel(pathText) > 3 && ...
        (pathText(end) == filesep || pathText(end) == '/')
        pathText(end) = [];
    end
end


function eegIndex = getEEGIndices(eegData)
    try
        eegIndex = eegData.indchantype('EEG');
    catch
        types = string(eegData.chantype);
        eegIndex = find(strcmpi(types,'EEG'));
    end
    eegIndex = eegIndex(:)';
end


function coordinates = get2DCoordinates(eegData,eegIndex)
    coordinates = [];

    try
        candidate = double(eegData.coor2D);
        if size(candidate,1) == 2 && size(candidate,2) >= max(eegIndex)
            coordinates = candidate(:,eegIndex)';
        elseif size(candidate,2) == 2 && size(candidate,1) >= max(eegIndex)
            coordinates = candidate(eegIndex,:);
        end
    catch
    end

    if isempty(coordinates) || any(~isfinite(coordinates),'all')
        try
            sensorStructure = sensors(eegData,'EEG');
            positions = double(sensorStructure.chanpos);
            labels = string(sensorStructure.label);
            wanted = string(eegData.chanlabels(eegIndex));
            [present,location] = ismember(lower(wanted),lower(labels));
            if ~all(present)
                error('A required check failed.');
            end

            positions = positions(location,:);
            coordinates = positions(:,1:2);
        catch
            error(['Could not obtain 2-D EEG sensor coordinates. Run SPM ' ...
                'Prepare > Project EEG sensors to 2D on the C*.mat files.']);
        end
    end

    coordinates = normalizeCoordinates(coordinates);
end


function coordinates = normalizeCoordinates(coordinates)
    coordinates = double(coordinates);
    coordinates = coordinates - mean(coordinates,1,'omitnan');
    radius = sqrt(sum(coordinates.^2,2));
    scale = max(radius);
    if ~(isfinite(scale) && scale > 0)
        error('The EEG sensor coordinates cannot be normalised.');
    end

    coordinates = coordinates ./ scale;
end


function [scaleToUv,unitText,isKnown] = getMicrovoltScale(eegData,channelIndex)
    unitText = 'native unit';
    isKnown = false;
    scaleToUv = 1;

    try
        unitsFound = units(eegData,channelIndex);
    catch
        try
            unitsFound = eegData.units(channelIndex);
        catch
            unitsFound = {};
        end
    end

    if ischar(unitsFound)
        unitsFound = cellstr(unitsFound);
    end
    if isstring(unitsFound)
        unitsFound = cellstr(unitsFound);
    end
    if isempty(unitsFound)
        return;
    end

    unitsFound = string(unitsFound(:));
    unitsFound = unitsFound(strlength(strtrim(unitsFound)) > 0);
    if isempty(unitsFound)
        return;
    end

    [uniqueUnits,~,unitIndex] = unique(lower(strtrim(unitsFound)),'stable');
    unitCounts = zeros(numel(uniqueUnits), 1);
    for channelNumber = 1:numel(unitIndex)
        currentUnitIndex = unitIndex(channelNumber);
        unitCounts(currentUnitIndex) = unitCounts(currentUnitIndex) + 1;
    end
    [~,mostFrequent] = max(unitCounts);
    unitText = char(uniqueUnits(mostFrequent));
    cleanUnit = lower(strtrim(string(unitText)));
    cleanUnit = replace(cleanUnit,["µ","μ"],"u");
    cleanUnit = erase(cleanUnit," ");

    switch cleanUnit
    case {"v","volt","volts"}
        scaleToUv = 1e6;
        isKnown = true;
    case {"mv","millivolt","millivolts"}
        scaleToUv = 1e3;
        isKnown = true;
    case {"uv","microvolt","microvolts"}
        scaleToUv = 1;
        isKnown = true;
    case {"nv","nanovolt","nanovolts"}
        scaleToUv = 1e-3;
        isKnown = true;
    end
end


function counts = readLatestEventCounts(rootFolder,subjectIDs)
    counts = nan(numel(subjectIDs),1);
    logs = dir(fullfile(rootFolder,'**','Convolution_log_*.csv'));
    if isempty(logs)
        warning(['No Convolution_log_*.csv was found. Clean E1 counts will ' ...
            'be reported as unavailable.']);
        return;
    end

    [~,order] = sort([logs.datenum],'descend');
    for logIndex = order
        try
            T = readtable(fullfile(logs(logIndex).folder,logs(logIndex).name), ...
                'TextType','string');
        catch
            continue;
        end
        if ~all(ismember({'Subject','CleanE1Count'},T.Properties.VariableNames))
            continue;
        end
        for row = 1:height(T)
            token = regexp(char(string(T.Subject(row))),'\d+','match','once');
            if isempty(token)
                continue;
            end
            id = str2double(token);
            position = find(subjectIDs == id,1);
            if ~isempty(position) && isnan(counts(position))
                counts(position) = double(T.CleanE1Count(row));
            end
        end
        if all(isfinite(counts))
            break;
        end
    end
end


function [rankValue,maxR2,medianR2,conditionNumber,R2] = ...
inspectSubjectDesign(datasetFile,expectedColumns,conditionName)
    rankValue = NaN;
    maxR2 = NaN;
    medianR2 = NaN;
    conditionNumber = NaN;
    R2 = [];

    datasetFolder = fileparts(datasetFile);
    spmFile = fullfile(datasetFolder,'SPM.mat');
    if ~isfile(spmFile)
        candidates = dir(fullfile(datasetFolder,'**','SPM.mat'));
        if numel(candidates) == 1
            spmFile = fullfile(candidates(1).folder,candidates(1).name);
        else
            return;
        end
    end

    try
        loaded = load(spmFile,'SPM');
        SPM = loaded.SPM;
        Xfull = double(SPM.xX.X);
        names = string(SPM.xX.name(:));
    catch
        return;
    end

    simpleNames = lower(regexprep(names,'\s+',''));
    conditionSimple = lower(regexprep(string(conditionName),'\s+',''));
    columns = find(contains(simpleNames,conditionSimple) & ...
        contains(simpleNames,'bf('));
    if numel(columns) ~= expectedColumns
        allBasisColumns = find(contains(simpleNames,'bf('));
        if numel(allBasisColumns) == expectedColumns
            columns = allBasisColumns;
        end
    end
    if numel(columns) ~= expectedColumns
        return;
    end

    X = Xfull(:,columns);
    X = X(all(isfinite(X),2),:);
    if isempty(X) || any(std(X,0,1) <= eps)
        return;
    end

    rankValue = rank(X);
    R = corrcoef(X);
    R = (R+R')/2;
    R2 = R.^2;
    offDiagonal = R2(triu(true(expectedColumns),1));
    offDiagonal = offDiagonal(isfinite(offDiagonal));
    maxR2 = max(offDiagonal);
    medianR2 = median(offDiagonal);

    Z = (X-mean(X,1))./std(X,0,1);
    singularValues = svd(Z,'econ');
    if singularValues(end) > eps(singularValues(1))*max(size(Z))
        conditionNumber = singularValues(1)/singularValues(end);
    else
        conditionNumber = Inf;
    end
end


function summary = makeModelQCSummary(T,study,usableDesigns)
    validEvents = T.CleanE1Count(isfinite(T.CleanE1Count));
    validRank = T.DesignRank(isfinite(T.DesignRank));
    validMaxR2 = T.MaximumOffDiagonalR2(isfinite(T.MaximumOffDiagonalR2));
    validCondition = T.StandardizedConditionNumber( ...
        isfinite(T.StandardizedConditionNumber));

    Measure = [ ...
        "Participants_total";"Participants_monolingual"; ...
        "Participants_bilingual";"EEG_channels";"Time_points"; ...
        "Window_start_ms";"Window_end_ms";"Fourier_basis_functions"; ...
        "Usable_design_matrices";"Full_rank_designs"; ...
        "Clean_E1_mean";"Clean_E1_SD";"Clean_E1_min";"Clean_E1_max"; ...
        "Maximum_off_diagonal_R2_mean"; ...
        "Maximum_off_diagonal_R2_SD"; ...
        "Maximum_off_diagonal_R2_min"; ...
        "Maximum_off_diagonal_R2_max"; ...
        "Condition_number_median";"Condition_number_min"; ...
        "Condition_number_max"];

    Value = nan(numel(Measure),1);
    Value(1:10) = [height(T);sum(T.Group == "Monolingual"); ...
        sum(T.Group == "Bilingual");mode(T.EEGChannels);mode(T.TimePoints); ...
        study.analysisWindowMs(1);study.analysisWindowMs(2); ...
        study.expectedBasisFunctions;usableDesigns; ...
        sum(validRank == study.expectedBasisFunctions)];

    if ~isempty(validEvents)
        Value(11:14) = [mean(validEvents);std(validEvents); ...
            min(validEvents);max(validEvents)];
    end
    if ~isempty(validMaxR2)
        Value(15:18) = [mean(validMaxR2);std(validMaxR2); ...
            min(validMaxR2);max(validMaxR2)];
    end
    if ~isempty(validCondition)
        Value(19:21) = [median(validCondition);min(validCondition); ...
            max(validCondition)];
    end

    summary = table(Measure,Value);
end


function makeDesignHeatmap(groupMeanR2,study,figureFolder)
    labels = strings(1,study.expectedBasisFunctions);
    labels(1) = "DC";
    labelPosition = 2;
    for harmonic = 1:12
        frequencyHz = harmonic/0.5;
        labels(labelPosition) = "sin"+string(frequencyHz)+"Hz";
        labels(labelPosition+1) = "cos"+string(frequencyHz)+"Hz";
        labelPosition = labelPosition+2;
    end

    fig = figure('Color','w','Position',[80 40 1150 980]);
    ax = axes(fig);
    imagesc(ax,groupMeanR2,[0 max(0.05,max(groupMeanR2(:)))]);
    axis(ax,'square');
    colormap(ax,parula(256));
    c = colorbar(ax);
    c.Label.String = 'Mean shared variance (R^2)';
    set(ax,'XTick',1:numel(labels),'YTick',1:numel(labels), ...
        'XTickLabel',labels,'YTickLabel',labels,'FontName','Arial', ...
        'FontSize',8,'TickDir','out');
    xtickangle(ax,90);
    xlabel(ax,'Fourier design columns');
    ylabel(ax,'Fourier design columns');
    title(ax,'Mean design-matrix shared variance across participants');
    exportFigure(fig,figureFolder,'Supplementary_design_matrix_R2_heatmap');
    close(fig);
end


function [windowTable,subjectTable] = makeWindowTables( ...
    data,timeMs,subjectIDs,groupCode,study,amplitudeUnit)
    numberOfRows = numel(study.clusterNames)*numel(study.windowNames);

    Cluster = strings(numberOfRows,1);
    Channels = strings(numberOfRows,1);
    Window = strings(numberOfRows,1);
    WindowStartMs = nan(numberOfRows,1);
    WindowEndMs = nan(numberOfRows,1);
    MonolingualN = nan(numberOfRows,1);
    MonolingualMean = nan(numberOfRows,1);
    MonolingualSD = nan(numberOfRows,1);
    MonolingualSEM = nan(numberOfRows,1);
    BilingualN = nan(numberOfRows,1);
    BilingualMean = nan(numberOfRows,1);
    BilingualSD = nan(numberOfRows,1);
    BilingualSEM = nan(numberOfRows,1);
    MeanDifference_Minus_B = nan(numberOfRows,1);
    DifferenceCI95Lower = nan(numberOfRows,1);
    DifferenceCI95Upper = nan(numberOfRows,1);
    HedgesG = nan(numberOfRows,1);
    AmplitudeUnit = repmat(string(amplitudeUnit),numberOfRows,1);

    subjectTable = table();
    row = 0;

    for clusterIndex = 1:numel(study.clusterNames)
        for windowIndex = 1:numel(study.windowNames)
            row = row+1;
            selectedTime = timeMs >= study.windowsMs(windowIndex,1) & ...
                timeMs <= study.windowsMs(windowIndex,2);
            if ~any(selectedTime)
                error('No samples in descriptive time window.');
            end


            values = squeeze(mean(data(:,clusterIndex,selectedTime),3,'omitnan'));
            values1 = values(groupCode == 1);
            values2 = values(groupCode == 2);
            statistics = twoGroupDescription(values1,values2);

            Cluster(row) = string(study.clusterNames{clusterIndex});
            Channels(row) = string(strjoin(study.clusterChannels{clusterIndex},', '));
            Window(row) = string(study.windowNames{windowIndex});
            WindowStartMs(row) = study.windowsMs(windowIndex,1);
            WindowEndMs(row) = study.windowsMs(windowIndex,2);
            MonolingualN(row) = statistics.n1;
            MonolingualMean(row) = statistics.mean1;
            MonolingualSD(row) = statistics.sd1;
            MonolingualSEM(row) = statistics.sem1;
            BilingualN(row) = statistics.n2;
            BilingualMean(row) = statistics.mean2;
            BilingualSD(row) = statistics.sd2;
            BilingualSEM(row) = statistics.sem2;
            MeanDifference_Minus_B(row) = statistics.difference;
            DifferenceCI95Lower(row) = statistics.ciLower;
            DifferenceCI95Upper(row) = statistics.ciUpper;
            HedgesG(row) = statistics.hedgesG;

            currentSubjectTable = table(subjectIDs(:), ...
                repmat(string(study.clusterNames{clusterIndex}),numel(subjectIDs),1), ...
                repmat(string(study.windowNames{windowIndex}),numel(subjectIDs),1), ...
                string(groupCode(:)),values(:), ...
                repmat(string(amplitudeUnit),numel(subjectIDs),1), ...
                'VariableNames',{'SubjectID','Cluster','Window','GroupCode', ...
                'MeanAmplitude','AmplitudeUnit'});
            currentSubjectTable.GroupCode(currentSubjectTable.GroupCode == "1") = ...
                "Monolingual";
            currentSubjectTable.GroupCode(currentSubjectTable.GroupCode == "2") = ...
                "Bilingual";
            subjectTable = [subjectTable;currentSubjectTable]; %#ok<AGROW>
        end
    end

    windowTable = table(Cluster,Channels,Window,WindowStartMs,WindowEndMs, ...
        MonolingualN,MonolingualMean,MonolingualSD,MonolingualSEM, ...
        BilingualN,BilingualMean,BilingualSD,BilingualSEM, ...
        MeanDifference_Minus_B,DifferenceCI95Lower,DifferenceCI95Upper, ...
        HedgesG,AmplitudeUnit);
end


function groupStatistics = twoGroupDescription(values1,values2)
    values1 = values1(isfinite(values1));
    values2 = values2(isfinite(values2));
    groupStatistics.n1 = numel(values1);
    groupStatistics.n2 = numel(values2);
    groupStatistics.mean1 = mean(values1);
    groupStatistics.mean2 = mean(values2);
    groupStatistics.sd1 = std(values1,0);
    groupStatistics.sd2 = std(values2,0);
    groupStatistics.sem1 = groupStatistics.sd1/sqrt(groupStatistics.n1);
    groupStatistics.sem2 = groupStatistics.sd2/sqrt(groupStatistics.n2);
    groupStatistics.difference = groupStatistics.mean1-groupStatistics.mean2;

    standardError = sqrt(groupStatistics.sd1^2/groupStatistics.n1+groupStatistics.sd2^2/groupStatistics.n2);
    welchDf = (groupStatistics.sd1^2/groupStatistics.n1+groupStatistics.sd2^2/groupStatistics.n2)^2 / ...
        ((groupStatistics.sd1^2/groupStatistics.n1)^2/(groupStatistics.n1-1)+(groupStatistics.sd2^2/groupStatistics.n2)^2/(groupStatistics.n2-1));
    if exist('tinv','file') == 2 && isfinite(welchDf)
        criticalValue = tinv(0.975,welchDf);
    else
        criticalValue = 1.96;
    end
    groupStatistics.ciLower = groupStatistics.difference-criticalValue*standardError;
    groupStatistics.ciUpper = groupStatistics.difference+criticalValue*standardError;

    pooledSD = sqrt(((groupStatistics.n1-1)*groupStatistics.sd1^2+(groupStatistics.n2-1)*groupStatistics.sd2^2) / ...
        (groupStatistics.n1+groupStatistics.n2-2));
    cohensD = groupStatistics.difference/pooledSD;
    smallSampleCorrection = 1-3/(4*(groupStatistics.n1+groupStatistics.n2)-9);
    groupStatistics.hedgesG = smallSampleCorrection*cohensD;
end


function T = makeTimePointTable(data,timeMs,groupCode,study,amplitudeUnit)
    T = table();
    for clusterIndex = 1:numel(study.clusterNames)
        values1 = squeeze(data(groupCode == 1,clusterIndex,:));
        values2 = squeeze(data(groupCode == 2,clusterIndex,:));
        numberOfTimePoints = numel(timeMs);
        mean1 = zeros(1, numberOfTimePoints);
        mean2 = zeros(1, numberOfTimePoints);
        sd1 = zeros(1, numberOfTimePoints);
        sd2 = zeros(1, numberOfTimePoints);
        n1 = zeros(1, numberOfTimePoints);
        n2 = zeros(1, numberOfTimePoints);
        sem1 = zeros(1, numberOfTimePoints);
        sem2 = zeros(1, numberOfTimePoints);
        difference = zeros(1, numberOfTimePoints);
        ciLower = zeros(1, numberOfTimePoints);
        ciUpper = zeros(1, numberOfTimePoints);

        for timeIndex = 1:numberOfTimePoints
            currentMono = values1(:, timeIndex);
            currentBi = values2(:, timeIndex);
            mean1(timeIndex) = mean(currentMono, 'omitnan');
            mean2(timeIndex) = mean(currentBi, 'omitnan');
            sd1(timeIndex) = std(currentMono, 0, 'omitnan');
            sd2(timeIndex) = std(currentBi, 0, 'omitnan');
            n1(timeIndex) = sum(isfinite(currentMono));
            n2(timeIndex) = sum(isfinite(currentBi));
            sem1(timeIndex) = sd1(timeIndex)/sqrt(n1(timeIndex));
            sem2(timeIndex) = sd2(timeIndex)/sqrt(n2(timeIndex));
            difference(timeIndex) = mean1(timeIndex) - mean2(timeIndex);

            monoVariance = sd1(timeIndex)^2/n1(timeIndex);
            biVariance = sd2(timeIndex)^2/n2(timeIndex);
            seDifference = sqrt(monoVariance + biVariance);
            welchDf = (monoVariance + biVariance)^2 / ...
                (monoVariance^2/(n1(timeIndex)-1) + biVariance^2/(n2(timeIndex)-1));
            if exist('tinv', 'file') == 2
                criticalValue = tinv(0.975, welchDf);
            else
                criticalValue = 1.96;
            end
            ciLower(timeIndex) = difference(timeIndex) - criticalValue*seDifference;
            ciUpper(timeIndex) = difference(timeIndex) + criticalValue*seDifference;
        end

        rows = numel(timeMs);
        current = table( ...
            repmat(string(study.clusterNames{clusterIndex}),rows,1), ...
            repmat(string(strjoin(study.clusterChannels{clusterIndex},', ')),rows,1), ...
            timeMs(:),n1(:),mean1(:),sd1(:),sem1(:), ...
            n2(:),mean2(:),sd2(:),sem2(:),difference(:), ...
            ciLower(:),ciUpper(:), ...
            repmat(string(amplitudeUnit),rows,1), ...
            'VariableNames',{'Cluster','Channels','TimeMs','MonolingualN', ...
            'MonolingualMean','MonolingualSD','MonolingualSEM','BilingualN', ...
            'BilingualMean','BilingualSD','BilingualSEM', ...
            'MeanDifference_Minus_B','DifferenceCI95Lower', ...
            'DifferenceCI95Upper','AmplitudeUnit'});
        T = [T;current]; %#ok<AGROW>
    end
end


function makeWaveformFigure(data,timeMs,groupCode,study, ...
    amplitudeLabel,figureFolder)
    fig = figure('Color','w','Position',[30 30 1900 1180]);
    layout = tiledlayout(fig,2,numel(study.clusterNames), ...
        'TileSpacing','loose','Padding','loose');
    layout.OuterPosition = [0.045 0.105 0.91 0.80];

    legendHandles = gobjects(2,1);
    allMeans = [];
    allDifferences = [];

    descriptive = cell(numel(study.clusterNames),1);
    for clusterIndex = 1:numel(study.clusterNames)
        values1 = squeeze(data(groupCode == 1,clusterIndex,:));
        values2 = squeeze(data(groupCode == 2,clusterIndex,:));
        d.mean1 = mean(values1,1,'omitnan');
        d.mean2 = mean(values2,1,'omitnan');
        d.sem1 = std(values1,0,1,'omitnan')./sqrt(sum(isfinite(values1),1));
        d.sem2 = std(values2,0,1,'omitnan')./sqrt(sum(isfinite(values2),1));
        d.difference = d.mean1-d.mean2;
        sd1 = std(values1,0,1,'omitnan');
        sd2 = std(values2,0,1,'omitnan');
        n1 = sum(isfinite(values1),1);
        n2 = sum(isfinite(values2),1);
        se = sqrt(sd1.^2./n1+sd2.^2./n2);
        df = (sd1.^2./n1+sd2.^2./n2).^2 ./ ...
            ((sd1.^2./n1).^2./(n1-1)+(sd2.^2./n2).^2./(n2-1));
        if exist('tinv','file') == 2
            critical = tinv(0.975,df);
        else
            critical = 1.96*ones(size(df));
        end
        d.ci = critical.*se;
        descriptive{clusterIndex} = d;
        allMeans = [allMeans d.mean1-d.sem1 d.mean1+d.sem1 ...
            d.mean2-d.sem2 d.mean2+d.sem2]; %#ok<AGROW>
        allDifferences = [allDifferences d.difference-d.ci ...
            d.difference+d.ci]; %#ok<AGROW>
    end

    meanLimits = paddedLimits(allMeans);
    differenceLimits = symmetricLimits(allDifferences);

    for clusterIndex = 1:numel(study.clusterNames)
        d = descriptive{clusterIndex};
        ax = nexttile(layout,clusterIndex);
        hold(ax,'on');
        shadedLine(ax,timeMs,d.mean1,d.sem1,study.monolingualColor);
        h1 = plot(ax,timeMs,d.mean1,'Color',study.monolingualColor, ...
            'LineWidth',2.2);
        shadedLine(ax,timeMs,d.mean2,d.sem2,study.bilingualColor);
        h2 = plot(ax,timeMs,d.mean2,'Color',study.bilingualColor, ...
            'LineWidth',2.2);
        if clusterIndex == 1
            legendHandles = [h1;h2];
        end
        xline(ax,0,'--','Color',[.35 .35 .35],'HandleVisibility','off');
        yline(ax,0,':','Color',[.35 .35 .35],'HandleVisibility','off');
        xlim(ax,study.analysisWindowMs);
        ylim(ax,meanLimits);
        xticks(ax,0:100:500);
        title(ax,{study.clusterNames{clusterIndex}; ...
            strjoin(study.clusterChannels{clusterIndex},', ')}, ...
            'FontWeight','bold','FontSize',11,'Interpreter','none');
        setPublicationStyle(ax);
        if clusterIndex == 1
            ylabel(ax,amplitudeLabel);
        end
        text(ax,0.02,0.95,char('A'+clusterIndex-1),'Units','normalized', ...
            'FontWeight','bold','FontSize',15,'VerticalAlignment','top');
        hold(ax,'off');

        ax = nexttile(layout,numel(study.clusterNames)+clusterIndex);
        hold(ax,'on');
        shadedLine(ax,timeMs,d.difference,d.ci,study.differenceColor);
        plot(ax,timeMs,d.difference,'Color',study.differenceColor, ...
            'LineWidth',2.2);
        xline(ax,0,'--','Color',[.35 .35 .35],'HandleVisibility','off');
        yline(ax,0,':','Color',[.35 .35 .35],'HandleVisibility','off');
        xlim(ax,study.analysisWindowMs);
        ylim(ax,differenceLimits);
        xticks(ax,0:100:500);
        xlabel(ax,'Time after E1 onset (ms)');
        title(ax,'Monolingual - Bilingual (95% CI)');
        setPublicationStyle(ax);
        if clusterIndex == 1
            ylabel(ax,['Group difference (' extractUnit(amplitudeLabel) ')']);
        end
        text(ax,0.02,0.95,char('D'+clusterIndex-1),'Units','normalized', ...
            'FontWeight','bold','FontSize',15,'VerticalAlignment','top');
        hold(ax,'off');
    end

    lgd = legend(legendHandles, ...
        {sprintf('Monolingual (n=%d)',sum(groupCode == 1)), ...
        sprintf('Bilingual (n=%d)',sum(groupCode == 2))}, ...
        'Orientation','horizontal','Box','off','FontName','Arial');
    lgd.FontSize = 10;
    lgd.Layout.Tile = 'south';
    title(layout,'Deconvolved all-images responses by posterior sensor cluster', ...
        'FontName','Arial','FontWeight','bold','FontSize',15);

    annotation(fig,'textbox',[0.12 0.018 0.76 0.036], ...
        'String',['Shading in A-C: +/-1 SEM. Shading in D-F: 95% CI. ' ...
        'No pointwise significance is implied.'], ...
        'EdgeColor','none','HorizontalAlignment','center', ...
        'FontName','Arial','FontAngle','italic','Color',[.3 .3 .3]);

    exportFigure(fig,figureFolder,'Figure_1_group_responses_and_differences');
    close(fig);
end


function [peakTable,topographyData] = makeTopographyFigure( ...
    data,timeMs,groupCode,coordinates,study,amplitudeUnit,figureFolder)
    mean1 = squeeze(mean(data(groupCode == 1,:,:),1,'omitnan'));
    mean2 = squeeze(mean(data(groupCode == 2,:,:),1,'omitnan'));
    equalWeightGrandMean = (mean1+mean2)./2;
    gfp = std(equalWeightGrandMean,0,1,'omitnan');

    numberOfWindows = size(study.topographySearchWindowsMs,1);
    peakLatencyMs = nan(numberOfWindows,1);
    peakGFP = nan(numberOfWindows,1);
    averageStartMs = nan(numberOfWindows,1);
    averageEndMs = nan(numberOfWindows,1);
    topographyData = struct([]);

    for i = 1:numberOfWindows
        searchMask = timeMs >= study.topographySearchWindowsMs(i,1) & ...
            timeMs <= study.topographySearchWindowsMs(i,2);
        searchIndices = find(searchMask);
        [peakGFP(i),relativeIndex] = max(gfp(searchIndices));
        peakIndex = searchIndices(relativeIndex);
        peakLatencyMs(i) = timeMs(peakIndex);
        averagingMask = timeMs >= peakLatencyMs(i)- ...
            study.topographyAverageHalfWidthMs & ...
            timeMs <= peakLatencyMs(i)+study.topographyAverageHalfWidthMs;
        averageStartMs(i) = min(timeMs(averagingMask));
        averageEndMs(i) = max(timeMs(averagingMask));
        topographyData(i).monolingual = mean(mean1(:,averagingMask),2,'omitnan');
        topographyData(i).bilingual = mean(mean2(:,averagingMask),2,'omitnan');
        topographyData(i).difference = topographyData(i).monolingual- ...
            topographyData(i).bilingual;
    end

    Window = string(study.topographyWindowNames(:));
    SearchStartMs = study.topographySearchWindowsMs(:,1);
    SearchEndMs = study.topographySearchWindowsMs(:,2);
    PeakLatencyMs = peakLatencyMs;
    PeakGFP = peakGFP;
    TopographyAverageStartMs = averageStartMs;
    TopographyAverageEndMs = averageEndMs;
    AmplitudeUnit = repmat(string(amplitudeUnit),numberOfWindows,1);
    SelectionRule = repmat("Equal-weight grand-mean GFP; group-blind", ...
        numberOfWindows,1);
    peakTable = table(Window,SearchStartMs,SearchEndMs,PeakLatencyMs, ...
        PeakGFP,TopographyAverageStartMs,TopographyAverageEndMs, ...
        AmplitudeUnit,SelectionRule);

    groupMaximum = 0;
    differenceMaximum = 0;
    for i = 1:numberOfWindows
        groupMaximum = max([groupMaximum; ...
            abs(topographyData(i).monolingual(:)); ...
            abs(topographyData(i).bilingual(:))]);
        differenceMaximum = max([differenceMaximum; ...
            abs(topographyData(i).difference(:))]);
    end
    if groupMaximum == 0
        groupMaximum = 1;
    end
    if differenceMaximum == 0
        differenceMaximum = 1;
    end

    fig = figure('Color','w','Position',[30 20 1600 1550]);
    layout = tiledlayout(fig,numberOfWindows,3, ...
        'TileSpacing','loose','Padding','loose');
    layout.OuterPosition = [0.065 0.105 0.89 0.79];
    maps = divergingMap(256);

    for i = 1:numberOfWindows
        values = {topographyData(i).monolingual, ...
            topographyData(i).bilingual,topographyData(i).difference};
        titles = {'Monolingual','Bilingual','Monolingual - Bilingual'};
        for column = 1:3
            ax = nexttile(layout,(i-1)*3+column);
            if column < 3
                limits = [-groupMaximum groupMaximum];
            else
                limits = [-differenceMaximum differenceMaximum];
            end
            plotScalpMap(ax,coordinates,values{column},limits,maps);
            if i == 1
                title(ax,titles{column},'FontWeight','bold','FontSize',12);
            end
            if column == 1
                text(ax,-1.18,1.17,sprintf('%s\n%.0f ms', ...
                    study.topographyWindowNames{i},peakLatencyMs(i)), ...
                    'HorizontalAlignment','left','VerticalAlignment','top', ...
                    'FontName','Arial','FontWeight','bold','FontSize',10, ...
                    'Clipping','on');
            end
        end
    end

    title(layout,['Scalp maps at group-blind grand-mean GFP peaks (' ...
        amplitudeUnit ')'],'FontName','Arial','FontWeight','bold','FontSize',15);
    annotation(fig,'textbox',[0.10 0.018 0.80 0.038], ...
        'String',['Latencies were selected from the equal-weight grand mean, ' ...
        'not from the group contrast. Sensor maps do not identify cortical sources.'], ...
        'EdgeColor','none','HorizontalAlignment','center', ...
        'FontName','Arial','FontAngle','italic','Color',[.3 .3 .3]);

    exportFigure(fig,figureFolder,'Figure_2_group_blind_scalp_maps');
    close(fig);
end


function plotScalpMap(ax,coordinates,values,limits,colorMap)
    x = coordinates(:,1);
    y = coordinates(:,2);
    values = double(values(:));
    valid = isfinite(x)&isfinite(y)&isfinite(values);
    x = x(valid);
    y = y(valid);
    values = values(valid);

    gridVector = linspace(-1.08,1.08,180);
    [X,Y] = meshgrid(gridVector,gridVector);
    interpolator = scatteredInterpolant(x,y,values,'natural','none');
    Z = interpolator(X,Y);
    mask = X.^2+Y.^2 <= 1.03^2;
    Z(~mask) = NaN;

    imageHandle = imagesc(ax,gridVector,gridVector,Z);
    set(imageHandle,'AlphaData',isfinite(Z));
    axis(ax,'xy');
    axis(ax,'image');
    axis(ax,'off');
    colormap(ax,colorMap);
    clim(ax,limits);
    hold(ax,'on');
    theta = linspace(0,2*pi,300);
    plot(ax,cos(theta),sin(theta),'Color',[.15 .15 .15],'LineWidth',1.2);
    plot(ax,[-.14 0 .14],[.99 1.17 .99],'Color',[.15 .15 .15], ...
        'LineWidth',1.2);
    scatter(ax,x,y,10,[.12 .12 .12],'filled','MarkerFaceAlpha',.65);
    xlim(ax,[-1.28 1.28]);
    ylim(ax,[-1.20 1.26]);
    c = colorbar(ax,'southoutside');
    c.FontName = 'Arial';
    c.FontSize = 7.5;
    hold(ax,'off');
end


function map = divergingMap(numberOfColors)
    anchors = [0.13 0.40 0.67;0.33 0.66 0.82;0.82 0.90 0.94; ...
        1 1 1;0.99 0.78 0.57;0.88 0.40 0.29;0.70 0.09 0.17];
    map = interp1(linspace(0,1,size(anchors,1)),anchors, ...
        linspace(0,1,numberOfColors),'linear');
    map = min(max(map,0),1);
end


function shadedLine(ax,x,meanValue,errorValue,colorValue)
    x = x(:);
    meanValue = meanValue(:);
    errorValue = errorValue(:);
    valid = isfinite(x)&isfinite(meanValue)&isfinite(errorValue);
    fill(ax,[x(valid);flipud(x(valid))], ...
        [meanValue(valid)-errorValue(valid); ...
        flipud(meanValue(valid)+errorValue(valid))], ...
        colorValue,'FaceAlpha',0.16,'EdgeColor','none', ...
        'HandleVisibility','off');
end


function limits = paddedLimits(values)
    values = values(isfinite(values));
    limits = [min(values) max(values)];
    padding = .08*diff(limits);
    if ~isfinite(padding) || padding == 0
        padding = 1;
    end
    limits = limits+[-padding padding];
end


function limits = symmetricLimits(values)
    values = values(isfinite(values));
    maximum = max(abs(values));
    if ~isfinite(maximum) || maximum == 0
        maximum = 1;
    end
    limits = [-1.08*maximum 1.08*maximum];
end


function unitText = extractUnit(amplitudeLabel)
    token = regexp(amplitudeLabel,'\(([^)]+)\)','tokens','once');
    if isempty(token)
        unitText = 'amplitude units';
    else
        unitText = token{1};
    end
end


function setPublicationStyle(ax)
    set(ax,'FontName','Arial','FontSize',10.5,'LineWidth',1, ...
        'TickDir','out','Box','off','Color','w','Layer','top');
    grid(ax,'on');
    ax.GridAlpha = .12;
end


function exportFigure(fig,folderName,baseName)
    exportgraphics(fig,fullfile(folderName,[baseName '.png']), ...
        'Resolution',600,'BackgroundColor','white');
    exportgraphics(fig,fullfile(folderName,[baseName '.pdf']), ...
        'ContentType','vector','BackgroundColor','white');
    savefig(fig,fullfile(folderName,[baseName '.fig']));
end


function created = writeWordResultsDocument(fileName,study,summary, ...
    windowTable,peakTable,amplitudeUnit)
% Create a genuine DOCX package directly from Office Open XML. Microsoft
% Word and ActiveX are deliberately not used here.
    created = false;
    packageFolder = '';

    try
        [headers1,body1,note1] = makeWordQCTable(summary);
        [headers2,body2,note2] = makeWordDescriptiveTable(windowTable,study, ...
            amplitudeUnit);
        [headers3,body3,note3] = makeWordTopographyTable(peakTable, ...
            amplitudeUnit);

        sections(1) = makeWordSection( ...
            'جدول ۱  خلاصه کنترل کیفیت مدل کانولوشنی', ...
            headers1,body1,note1,10,[72 28],false); %#ok<AGROW>
        sections(2) = makeWordSection( ...
            'جدول ۲  خلاصه توصیفی پاسخ‌ها در خوشه‌ها و پنجره‌های زمانی', ...
            headers2,body2,note2,9,[15 15 10 14 14 20 6 6],true); %#ok<AGROW>
        sections(3) = makeWordSection( ...
            'جدول ۳  زمان‌های انتخاب‌شده برای نقشه‌های پوست سر', ...
            headers3,body3,note3,9.5,[17 17 16 21 15 14],true); %#ok<AGROW>

        packageFolder = tempname;
        mkdir(packageFolder);
        mkdir(fullfile(packageFolder,'_rels'));
        mkdir(fullfile(packageFolder,'word'));
        mkdir(fullfile(packageFolder,'word','_rels'));

        writeUtf8File(fullfile(packageFolder,'[Content_Types].xml'), ...
            makeDocxContentTypesXml());
        writeUtf8File(fullfile(packageFolder,'_rels','.rels'), ...
            makeDocxRootRelationshipsXml());
        writeUtf8File(fullfile(packageFolder,'word','_rels', ...
            'document.xml.rels'),makeDocxDocumentRelationshipsXml());
        writeUtf8File(fullfile(packageFolder,'word','styles.xml'), ...
            makeDocxStylesXml());
        writeUtf8File(fullfile(packageFolder,'word','document.xml'), ...
            makeDocxDocumentXml(sections));

        zipFile = fullfile(packageFolder,'Convolution_GLM_Results_Tables.zip');
        zip(zipFile,{'[Content_Types].xml','_rels','word'},packageFolder);
        if ~isfile(zipFile)
            error('MATLAB did not create the temporary DOCX archive.');
        end


        % Use the Java file method only for an existing output. This avoids the
        % MATLAB delete name conflict reported when a user script is delete.m.
        if isfile(fileName)
            existingOutput = java.io.File(fileName);
            if ~(existingOutput.delete())
                error(['The previous DOCX could not be replaced. Close it in Word ' ...
                    'and run the script again: %s'],fileName);
            end

        end
        [copied,copyMessage] = copyfile(zipFile,fileName);
        if ~(copied)
            error('Could not write %s: %s',fileName,copyMessage);
        end

        outputInfo = dir(fileName);
        if ~(~isempty(outputInfo) && outputInfo.bytes > 0)
            error('The DOCX output file is empty.');
        end

        created = true;

    catch ME
        warning('Could not create the DOCX results tables: %s',ME.message);
    end

    if ~isempty(packageFolder) && isfolder(packageFolder)
        try
            rmdir(packageFolder,'s');
        catch cleanupError
            warning('The temporary DOCX folder could not be removed: %s', ...
                cleanupError.message);
        end
    end
end


function [headers,body,note] = makeWordQCTable(summary)


    headers = {'شاخص','مقدار'};
    body = { ...
        'شرکت‌کنندگان',sprintf('%d نفر  %d تک‌زبانه و %d دوزبانه', ...
        getSummaryValue(summary, "Participants_total"),getSummaryValue(summary, "Participants_monolingual"), ...
        getSummaryValue(summary, "Participants_bilingual")); ...
        'کانال‌های EEG',formatWordNumber(getSummaryValue(summary, "EEG_channels"),0); ...
        'نقاط زمانی',formatWordNumber(getSummaryValue(summary, "Time_points"),0); ...
        'بازه تحلیل',sprintf('%.0f تا %.0f میلی‌ثانیه', ...
        getSummaryValue(summary, "Window_start_ms"),getSummaryValue(summary, "Window_end_ms")); ...
        'توابع پایه فوریه',formatWordNumber( ...
        getSummaryValue(summary, "Fourier_basis_functions"),0); ...
        'ماتریس‌های طراحی قابل بررسی',sprintf('%.0f از %.0f', ...
        getSummaryValue(summary, "Usable_design_matrices"),getSummaryValue(summary, "Participants_total")); ...
        'ماتریس‌های دارای رتبه کامل ۲۵',formatWordNumber( ...
        getSummaryValue(summary, "Full_rank_designs"),0); ...
        'تعداد رویدادهای سالم E1',formatMeanSdRange( ...
        getSummaryValue(summary, "Clean_E1_mean"),getSummaryValue(summary, "Clean_E1_SD"), ...
        getSummaryValue(summary, "Clean_E1_min"),getSummaryValue(summary, "Clean_E1_max"),1); ...
        'بیشینه R² خارج از قطر',formatMeanSdRange( ...
        getSummaryValue(summary, "Maximum_off_diagonal_R2_mean"), ...
        getSummaryValue(summary, "Maximum_off_diagonal_R2_SD"), ...
        getSummaryValue(summary, "Maximum_off_diagonal_R2_min"), ...
        getSummaryValue(summary, "Maximum_off_diagonal_R2_max"),4); ...
        'عدد وضعیت ماتریس استانداردشده',formatMedianRange( ...
        getSummaryValue(summary, "Condition_number_median"), ...
        getSummaryValue(summary, "Condition_number_min"), ...
        getSummaryValue(summary, "Condition_number_max"),3)};

    note = ['یادداشت: R² خارج از قطر، واریانس مشترک میان ستون‌های متفاوت ' ...
        'ماتریس طراحی را نشان می‌دهد.'];
end


function [headers,body,note] = makeWordDescriptiveTable(T,study, ...
    amplitudeUnit)
    headers = {'خوشه حسگری','الکترودها','بازه زمانی', ...
        'تک‌زبانه M و SD','دوزبانه M و SD', ...
        'اختلاف میانگین و CI 95 درصد','Hedges g','واحد'};
    body = cell(height(T),numel(headers));

    for row = 1:height(T)
        body{row,1} = translateClusterName(T.Cluster(row));
        body{row,2} = char(T.Channels(row));
        body{row,3} = sprintf('%.0f-%.0f ms', ...
            T.WindowStartMs(row),T.WindowEndMs(row));
        body{row,4} = sprintf('%.3f (%.3f)  n=%d', ...
            T.MonolingualMean(row),T.MonolingualSD(row), ...
            T.MonolingualN(row));
        body{row,5} = sprintf('%.3f (%.3f)  n=%d', ...
            T.BilingualMean(row),T.BilingualSD(row), ...
            T.BilingualN(row));
        body{row,6} = sprintf('%.3f [%.3f, %.3f]', ...
            T.MeanDifference_Minus_B(row),T.DifferenceCI95Lower(row), ...
            T.DifferenceCI95Upper(row));
        body{row,7} = sprintf('%.3f',T.HedgesG(row));
        body{row,8} = translateAmplitudeUnit(amplitudeUnit);
    end

    note = sprintf(['یادداشت: اختلاف میانگین به‌صورت تک‌زبانه منهای ' ...
        'دوزبانه محاسبه شده است. مقادیر این جدول توصیفی‌اند و آزمون ' ...
        'معنی‌داری محسوب نمی‌شوند. خوشه‌ها شامل %s هستند.'], ...
        char(strjoin(string(study.clusterNames), '، ')));
end


function [headers,body,note] = makeWordTopographyTable(T,amplitudeUnit)
    headers = {'بازه','پنجره جستجو','زمان قله GFP', ...
        'پنجره میانگین‌گیری نقشه','GFP قله','واحد'};
    body = cell(height(T),numel(headers));

    for row = 1:height(T)
        body{row,1} = translateTopographyWindow(T.Window(row));
        body{row,2} = sprintf('%.0f-%.0f ms', ...
            T.SearchStartMs(row),T.SearchEndMs(row));
        body{row,3} = sprintf('%.1f ms',T.PeakLatencyMs(row));
        body{row,4} = sprintf('%.1f-%.1f ms', ...
            T.TopographyAverageStartMs(row), ...
            T.TopographyAverageEndMs(row));
        body{row,5} = sprintf('%.3f',T.PeakGFP(row));
        body{row,6} = translateAmplitudeUnit(amplitudeUnit);
    end

    note = ['یادداشت: زمان‌ها بر اساس قله GFP در میانگین بزرگِ هم‌وزن ' ...
        'دو گروه انتخاب شده‌اند و از کنتراست بین‌گروهی انتخاب نشده‌اند.'];
end


function section = makeWordSection(titleText,headers,body,noteText, ...
    fontSize,columnWidths,pageBreakBefore)
    section = struct('title',titleText,'headers',{headers},'body',{body}, ...
        'note',noteText,'fontSize',fontSize,'columnWidths',columnWidths, ...
        'pageBreakBefore',pageBreakBefore);
end


function xml = makeDocxDocumentXml(sections)
    parts = cell(1,2+3*numel(sections));
    part = 0;
    part = part+1;
    parts{part} = [ ...
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' ...
        '<w:document xmlns:w="http://schemas.openxmlformats.org/' ...
        'wordprocessingml/2006/main"><w:body>'];

    part = part+1;
    parts{part} = makeWordParagraphXml( ...
        'جداول نتایج مدل خطی عمومی کانولوشنی',16,true,'center',0,240,false);
    part = part+1;
    parts{part} = makeWordParagraphXml( ...
        ['این سند شامل جدول‌های اصلی کنترل کیفیت مدل، خلاصه توصیفی ' ...
        'پاسخ‌های برآوردشده و زمان‌های انتخاب‌شده برای نقشه‌های پوست سر ' ...
        'است. جدول‌ها برای درج مستقیم در فصل نتایج پایان‌نامه تنظیم شده‌اند.'], ...
        11,false,'right',0,240,false);

    for sectionIndex = 1:numel(sections)
        section = sections(sectionIndex);
        part = part+1;
        parts{part} = makeWordParagraphXml(section.title,13,true,'right', ...
            0,140,section.pageBreakBefore);
        part = part+1;
        parts{part} = makeWordTableXml(section.headers,section.body, ...
            section.fontSize,section.columnWidths);
        part = part+1;
        parts{part} = makeWordParagraphXml(section.note,9,false,'right', ...
            100,220,false);
    end

    % A4 landscape; 2-cm top/bottom margins and approximately 1.27-cm side
    % margins leave breathing room while retaining enough width for Table 2.
    part = part+1;
    parts{part} = [ ...
        '<w:sectPr><w:pgSz w:w="16838" w:h="11906" ' ...
        'w:orient="landscape"/><w:pgMar w:top="1134" w:right="720" ' ...
        'w:bottom="1134" w:left="720" w:header="360" w:footer="360" ' ...
        'w:gutter="0"/></w:sectPr></w:body></w:document>'];
    parts = parts(1:part);
    xml = [parts{:}];
end


function xml = makeWordTableXml(headers,body,fontSize,columnWidths)
    numberOfColumns = numel(headers);
    if ~(size(body,2) == numberOfColumns)
        error('The Word table body does not match its header width.');
    end

    if ~(numel(columnWidths) == numberOfColumns)
        error('The Word table column-width vector has the wrong length.');
    end


    contentWidth = 15398;
    columnWidths = double(columnWidths(:)');
    columnTwips = round(contentWidth*columnWidths/sum(columnWidths));
    columnTwips(end) = columnTwips(end)+contentWidth-sum(columnTwips);

    parts = cell(1,4+(size(body,1)+1)*(numberOfColumns+1));
    part = 0;
    part = part+1;
    parts{part} = [ ...
        '<w:tbl><w:tblPr><w:bidiVisual/>' ...
        '<w:tblW w:w="15398" w:type="dxa"/>' ...
        '<w:tblBorders>' ...
        '<w:top w:val="single" w:sz="4" w:color="D9D9D9"/>' ...
        '<w:left w:val="single" w:sz="4" w:color="D9D9D9"/>' ...
        '<w:bottom w:val="single" w:sz="4" w:color="D9D9D9"/>' ...
        '<w:right w:val="single" w:sz="4" w:color="D9D9D9"/>' ...
        '<w:insideH w:val="single" w:sz="4" w:color="D9D9D9"/>' ...
        '<w:insideV w:val="single" w:sz="4" w:color="D9D9D9"/>' ...
        '</w:tblBorders><w:tblLayout w:type="fixed"/><w:tblCellMar>' ...
        '<w:top w:w="90" w:type="dxa"/><w:left w:w="90" w:type="dxa"/>' ...
        '<w:bottom w:w="90" w:type="dxa"/><w:right w:w="90" w:type="dxa"/>' ...
        '</w:tblCellMar></w:tblPr><w:tblGrid>'];
    for column = 1:numberOfColumns
        parts{part} = [parts{part} sprintf('<w:gridCol w:w="%d"/>', ...
            columnTwips(column))];
    end
    parts{part} = [parts{part} '</w:tblGrid>'];

    part = part+1;
    parts{part} = '<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>';
    for column = 1:numberOfColumns
        part = part+1;
        parts{part} = makeWordTableCellXml(headers{column}, ...
            columnTwips(column),fontSize,true,false);
    end
    part = part+1;
    parts{part} = '</w:tr>';

    for row = 1:size(body,1)
        part = part+1;
        parts{part} = '<w:tr><w:trPr><w:cantSplit/></w:trPr>';
        alternateRow = mod(row,2) == 0;
        for column = 1:numberOfColumns
            part = part+1;
            parts{part} = makeWordTableCellXml(body{row,column}, ...
                columnTwips(column),fontSize,false,alternateRow);
        end
        part = part+1;
        parts{part} = '</w:tr>';
    end

    part = part+1;
    parts{part} = '</w:tbl>';
    parts = parts(1:part);
    xml = [parts{:}];
end


function xml = makeWordTableCellXml(textValue,widthTwips,fontSize, ...
    isHeader,isAlternate)
    textValue = char(string(textValue));
    if isHeader
        fillColor = '1F4E79';
        textColor = 'FFFFFF';
        boldXml = '<w:b/><w:bCs/>';
    elseif isAlternate
        fillColor = 'EDF4FA';
        textColor = '000000';
        boldXml = '';
    else
        fillColor = 'FFFFFF';
        textColor = '000000';
        boldXml = '';
    end

    % Numerical/statistical cells must remain left-to-right so values such as
    % 0.134 [-0.150, 0.418] are not visually reversed by Word's bidi engine.
    % Persian headers and Persian-only body cells remain right-to-left.
    if isHeader || isempty(regexp(textValue,'[A-Za-z\[\]\(\)=.,-]','once'))
        bidiXml = '<w:bidi/>';
        rtlXml = '<w:rtl/>';
    else
        bidiXml = '<w:bidi w:val="0"/>';
        rtlXml = '<w:rtl w:val="0"/>';
    end

    fontHalfPoints = round(2*fontSize);
    xml = sprintf([ ...
        '<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/>' ...
        '<w:shd w:val="clear" w:color="auto" w:fill="%s"/>' ...
        '<w:vAlign w:val="center"/></w:tcPr>' ...
        '<w:p><w:pPr>%s<w:spacing w:before="0" w:after="0" ' ...
        'w:line="240" w:lineRule="auto"/><w:jc w:val="center"/>' ...
        '</w:pPr><w:r><w:rPr>' ...
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="B Nazanin"/>' ...
        '%s<w:color w:val="%s"/><w:sz w:val="%d"/>' ...
        '<w:szCs w:val="%d"/>%s</w:rPr>' ...
        '<w:t xml:space="preserve">%s</w:t>' ...
        '</w:r></w:p></w:tc>'],widthTwips,fillColor,bidiXml,boldXml, ...
        textColor,fontHalfPoints,fontHalfPoints,rtlXml,escapeWordXml(textValue));
end


function xml = makeWordParagraphXml(textValue,fontSize,isBold,alignment, ...
    spaceBefore,spaceAfter,pageBreakBefore)
    if isBold
        boldXml = '<w:b/><w:bCs/>';
    else
        boldXml = '';
    end
    if pageBreakBefore
        pageBreakXml = '<w:pageBreakBefore/>';
    else
        pageBreakXml = '';
    end
    fontHalfPoints = round(2*fontSize);
    xml = sprintf([ ...
        '<w:p><w:pPr>%s<w:bidi/>' ...
        '<w:spacing w:before="%d" w:after="%d" w:line="276" ' ...
        'w:lineRule="auto"/><w:jc w:val="%s"/></w:pPr><w:r><w:rPr>' ...
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="B Nazanin"/>' ...
        '%s<w:color w:val="000000"/><w:sz w:val="%d"/>' ...
        '<w:szCs w:val="%d"/><w:rtl/></w:rPr>' ...
        '<w:t xml:space="preserve">%s</w:t>' ...
        '</w:r></w:p>'],pageBreakXml,spaceBefore,spaceAfter,alignment, ...
        boldXml,fontHalfPoints,fontHalfPoints,escapeWordXml(textValue));
end


function textValue = escapeWordXml(textValue)
    textValue = char(string(textValue));
    textValue = regexprep(textValue,'[\x00-\x08\x0B\x0C\x0E-\x1F]','');
    textValue = strrep(textValue,'&','&amp;');
    textValue = strrep(textValue,'<','&lt;');
    textValue = strrep(textValue,'>','&gt;');
end


function writeUtf8File(fileName,textValue)
    fid = fopen(fileName,'w','n','UTF-8');
    if ~(fid ~= -1)
        error('Could not create temporary DOCX part: %s',fileName);
    end

    bytesWritten = fwrite(fid,unicode2native(textValue,'UTF-8'),'uint8');
    closeStatus = fclose(fid);
    if ~(bytesWritten > 0 && closeStatus == 0)
        error('Could not finish writing temporary DOCX part: %s',fileName);
    end

end


function xml = makeDocxContentTypesXml()
    xml = [ ...
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' ...
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' ...
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-' ...
        'package.relationships+xml"/><Default Extension="xml" ' ...
        'ContentType="application/xml"/><Override PartName="/word/document.xml" ' ...
        'ContentType="application/vnd.openxmlformats-officedocument.' ...
        'wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ' ...
        'ContentType="application/vnd.openxmlformats-officedocument.' ...
        'wordprocessingml.styles+xml"/></Types>'];
end


function xml = makeDocxRootRelationshipsXml()
    xml = [ ...
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' ...
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' ...
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/' ...
        'officeDocument/2006/relationships/officeDocument" ' ...
        'Target="word/document.xml"/></Relationships>'];
end


function xml = makeDocxDocumentRelationshipsXml()
    xml = [ ...
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' ...
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' ...
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/' ...
        'officeDocument/2006/relationships/styles" ' ...
        'Target="styles.xml"/></Relationships>'];
end


function xml = makeDocxStylesXml()
    xml = [ ...
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' ...
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/' ...
        'wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>' ...
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="B Nazanin"/>' ...
        '<w:lang w:val="en-US" w:bidi="fa-IR"/></w:rPr></w:rPrDefault>' ...
        '<w:pPrDefault><w:pPr><w:bidi/><w:spacing w:after="120"/>' ...
        '</w:pPr></w:pPrDefault></w:docDefaults>' ...
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">' ...
        '<w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'];
end


function textValue = formatWordNumber(value,decimalPlaces)
    if isempty(value) || ~isfinite(value)
        textValue = 'در دسترس نیست';
    else
        textValue = sprintf(['%.' num2str(decimalPlaces) 'f'],value);
    end
end


function textValue = formatMeanSdRange(meanValue,sdValue,minValue, ...
    maxValue,decimalPlaces)
    if any(~isfinite([meanValue sdValue minValue maxValue]))
        textValue = 'در دسترس نیست';
        return;
    end
    formatText = ['M=%.' num2str(decimalPlaces) 'f; SD=%.' ...
        num2str(decimalPlaces) 'f; range=%.' num2str(decimalPlaces) ...
        'f-%.' num2str(decimalPlaces) 'f'];
    textValue = sprintf(formatText,meanValue,sdValue,minValue,maxValue);
end


function textValue = formatMedianRange(medianValue,minValue,maxValue, ...
    decimalPlaces)
    if any(~isfinite([medianValue minValue maxValue]))
        textValue = 'در دسترس نیست';
        return;
    end
    formatText = ['Median=%.' num2str(decimalPlaces) 'f; range=%.' ...
        num2str(decimalPlaces) 'f-%.' num2str(decimalPlaces) 'f'];
    textValue = sprintf(formatText,medianValue,minValue,maxValue);
end


function name = translateClusterName(inputName)
    switch lower(strtrim(char(string(inputName))))
    case 'medial occipital'
        name = 'پس‌سری میانی';
    case 'lateral occipital'
        name = 'پس‌سری جانبی';
    case 'occipitotemporal'
        name = 'پس‌سری گیجگاهی';
    otherwise
        name = char(string(inputName));
    end
end


function name = translateTopographyWindow(inputName)
    switch lower(strtrim(char(string(inputName))))
    case 'early'
        name = 'زودهنگام';
    case 'middle'
        name = 'میانی';
    case 'late'
        name = 'دیرهنگام';
    otherwise
        name = char(string(inputName));
    end
end


function unitText = translateAmplitudeUnit(amplitudeUnit)
    cleanUnit = lower(strtrim(char(string(amplitudeUnit))));
    if any(strcmp(cleanUnit,{'microvolts','microvolt','uv','µv','μv'}))
        unitText = 'میکروولت';
    else
        unitText = char(string(amplitudeUnit));
    end
end


function writeReportingGuide(fileName,study,summary,peakTable,amplitudeUnit)
    fid = fopen(fileName,'w','n','UTF-8');
    if ~(fid ~= -1)
        error('Could not create reporting guide.');
    end

    try


        fprintf(fid,'راهنمای گزارش نتایج مدل خطی عمومی کانولوشنی\n');
        fprintf(fid,'================================================\n\n');
        fprintf(fid,'نمونه نهایی: %d نفر (%d تک‌زبانه و %d دوزبانه).\n', ...
            getSummaryValue(summary, "Participants_total"),getSummaryValue(summary, "Participants_monolingual"), ...
            getSummaryValue(summary, "Participants_bilingual"));
        fprintf(fid,['پاسخ برآوردشده برای شرط all_images در %d کانال و بازه %d تا %d ' ...
            'میلی‌ثانیه بررسی شد. واحد دامنه: %s.\n\n'], ...
            getSummaryValue(summary, "EEG_channels"),getSummaryValue(summary, "Window_start_ms"), ...
            getSummaryValue(summary, "Window_end_ms"),amplitudeUnit);

        fprintf(fid,'۱) کنترل کیفیت مدل که باید در نتایج گزارش شود\n');
        fprintf(fid,'- تعداد ماتریس‌های طراحی قابل بررسی: %.0f از %.0f.\n', ...
            getSummaryValue(summary, "Usable_design_matrices"),getSummaryValue(summary, "Participants_total"));
        fprintf(fid,'- تعداد ماتریس‌های دارای رتبه کامل ۲۵: %.0f.\n', ...
            getSummaryValue(summary, "Full_rank_designs"));
        fprintf(fid,['- بیشینه واریانس مشترک خارج از قطر: میانگین %.4f، ' ...
            'انحراف معیار %.4f، دامنه %.4f تا %.4f.\n'], ...
            getSummaryValue(summary, "Maximum_off_diagonal_R2_mean"), ...
            getSummaryValue(summary, "Maximum_off_diagonal_R2_SD"), ...
            getSummaryValue(summary, "Maximum_off_diagonal_R2_min"), ...
            getSummaryValue(summary, "Maximum_off_diagonal_R2_max"));
        fprintf(fid,['- عدد وضعیت ماتریس استانداردشده: میانه %.3f، دامنه %.3f تا %.3f.\n'], ...
            getSummaryValue(summary, "Condition_number_median"),getSummaryValue(summary, "Condition_number_min"), ...
            getSummaryValue(summary, "Condition_number_max"));
        if isfinite(getSummaryValue(summary, "Clean_E1_mean"))
            fprintf(fid,['- تعداد رویدادهای پاک E1: میانگین %.1f، انحراف معیار %.1f، ' ...
                'دامنه %.0f تا %.0f.\n'],getSummaryValue(summary, "Clean_E1_mean"), ...
                getSummaryValue(summary, "Clean_E1_SD"),getSummaryValue(summary, "Clean_E1_min"),getSummaryValue(summary, "Clean_E1_max"));
        end

        fprintf(fid,'\n۲) شکل اصلی پاسخ‌ها\n');
        fprintf(fid,['- Figure_1: در ردیف بالا میانگین ± SEM دو گروه و در ردیف پایین ' ...
            'اختلاف تک‌زبانه منهای دوزبانه با فاصله اطمینان ۹۵%% نشان داده شده است.\n']);
        fprintf(fid,['- هم‌پوشانی یا عدم هم‌پوشانی SEM آزمون معنی‌داری نیست. از روی این ' ...
            'شکل علامت ستاره یا ادعای تفاوت آماری اضافه نکن.\n']);

        fprintf(fid,'\n۳) نقشه‌های پوست سر\n');
        for i = 1:height(peakTable)
            fprintf(fid,'- %s: قله GFP در %.1f ms؛ میانگین نقشه از %.1f تا %.1f ms.\n', ...
                char(peakTable.Window(i)),peakTable.PeakLatencyMs(i), ...
                peakTable.TopographyAverageStartMs(i), ...
                peakTable.TopographyAverageEndMs(i));
        end
        fprintf(fid,['- این زمان‌ها از میانگین بزرگِ هم‌وزن دو گروه انتخاب شده‌اند، نه ' ...
            'از کنتراست گروهی؛ بنابراین برای نمایش توصیفی دچار انتخاب بر اساس تفاوت گروهی نیستند.\n']);
        fprintf(fid,['- این نقشه‌ها نقشه حسگر هستند و نباید به‌عنوان فعال‌شدن EVC، LOC، ' ...
            'VTC یا هر منبع قشری گزارش شوند.\n']);

        fprintf(fid,'\n۴) جدول توصیفی\n');
        fprintf(fid,['- Table_2 را برای میانگین، SD، SEM، اختلاف میانگین، CI95%% و Hedges g ' ...
            'در خوشه‌ها و پنجره‌های ثابت استفاده کن. اگر پنجره‌ها پیش از مشاهده کنتراست ' ...
            'گروهی تعریف نشده‌اند، آن‌ها را صریحاً توصیفی/اکتشافی بنام.\n']);
        fprintf(fid,['- در این جدول p-value وجود ندارد؛ این اعداد توصیفی‌اند. آزمون استنباطی ' ...
            'اصلی در بخش تحلیل فضای حسگر SPM گزارش می‌شود.\n']);

        fprintf(fid,'\n۵) نتیجه استنباطی بین دو گروه\n');
        fprintf(fid,['- نتیجه کنتراست‌های Monolingual > Bilingual و Bilingual > Monolingual ' ...
            'را فقط از تحلیل SPM scalp-by-time گزارش کن.\n']);
        fprintf(fid,['- اگر هیچ خوشه/وکسل در آستانه تصحیح‌شده از چندگانگی باقی نمانده است، ' ...
            'صریحاً هر دو جهت را غیرمعنی‌دار گزارش کن؛ نمودارهای توصیفی جایگزین این نتیجه نیستند.\n']);

        fprintf(fid,'\n۶) آنچه نباید به این بخش اضافه شود\n');
        fprintf(fid,['- آزمون t نقطه‌به‌نقطه، علامت‌گذاری زمان‌های بدون تصحیح، انتخاب پنجره ' ...
            'بر اساس بیشترین تفاوت دو گروه، یا آزمون permutation دوم روی همان داده‌ها.\n']);
        fprintf(fid,['- نام‌گذاری قطعی مؤلفه‌های ERP یا نواحی مغزی صرفاً بر پایه زمان یا ' ...
            'محل الکترود.\n']);

        fprintf(fid,'\nخروجی‌های پیشنهادی برای متن اصلی\n');
        fprintf(fid,'- Figure_1_group_responses_and_differences\n');
        fprintf(fid,'- Figure_2_group_blind_scalp_maps\n');
        fprintf(fid,'- Convolution_GLM_Results_Tables.docx شامل جدول‌های ۱ تا ۳\n');
        fprintf(fid,'- نتیجه استنباطی تحلیل مستقل SPM sensor-space\n');

        fprintf(fid,'\nخروجی‌های مناسب پیوست\n');
        fprintf(fid,'- Supplementary_design_matrix_R2_heatmap\n');
        fprintf(fid,['- داده‌های کامل آزمودنی، پنجره و نقاط زمانی در فایل ' ...
            'convolution_glm_results_data.mat ذخیره شده‌اند.\n']);

        fprintf(fid,'\nتنظیمات ثبت‌شده در این اجرا\n');
        fprintf(fid,'- شرط: %s\n',char(string(study.condition)));
        fprintf(fid,'- خوشه‌ها: %s\n', ...
            char(strjoin(string(study.clusterNames),'; ')));

    catch cleanupError
        fclose(fid);
        rethrow(cleanupError);
    end
    fclose(fid);
end


function result = getSummaryValue(summary, measureName)
    matchingRows = false(height(summary), 1);
    for rowNumber = 1:height(summary)
        if summary.Measure(rowNumber) == measureName
            matchingRows(rowNumber) = true;
        end
    end
    result = summary.Value(matchingRows);
end
