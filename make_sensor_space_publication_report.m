%% make_sensor_space_publication_report.m
% Publication-quality reporting for an SPM25 sensor-space group analysis.
%
% WHAT THIS SCRIPT READS
%   - The estimated second-level SPM.mat.
%   - The subject images already listed in SPM.xY.P.
%   - The existing T-contrasts in SPM.xCon.
%
% WHAT THIS SCRIPT WRITES
%   - Exact SPM result tables (CSV) at voxel-level FWE p < .05, k = 0.
%   - A clean combined peak table and a one-row-per-contrast summary.
%   - Editable, fully labelled thesis tables that open directly in Word.
%   - A methods/Results draft in Markdown.
%   - Publication figures in 600-dpi PNG and vector PDF.
%
% IMPORTANT
%   - The first two coordinates are SENSOR-IMAGE coordinates (mm), not MNI.
%   - The third coordinate is latency (ms).
%   - Peak plots are descriptive because the peak was selected from the
%     same inferential map; do not treat them as an independent ROI test.
%
% Tested design assumptions for this study:
%   Group 1 = Monolingual (n = 20)
%   Group 2 = Bilingual   (n = 23)
%   Unequal variance two-sample t-test, df = 41


clearvars;
clc;

%% ======================= ONLY EDIT THIS LINE ==========================
resultsDir = 'E:\Subjects44\SPM_MAT_DAT\results_of_smooth';
% ======================================================================

%% Study metadata retained from the completed pipeline
study.groupNames = ["Monolingual", "Bilingual"];
study.expectedGroupN = [20 23];
study.condition = "all_images";
study.conversionMode = "Scalp x Time";
study.sensorType = "EEG";
study.timeWindowMs = [0 400];
study.expectedImageSize = [32 32 103];
study.appliedSmoothingFWHM = [5 5 10];  % mm, mm, ms
study.voxelFWE = 0.05;
study.extentThreshold = 0;
study.localMaximumDistanceMm = 8;

% Desired directional contrasts. If duplicate contrasts exist, the first
% matching contrast is used and a warning is printed.
contrastSpec(1).name = "Monolingual > Bilingual";
contrastSpec(1).weights = [1; -1];
contrastSpec(2).name = "Bilingual > Monolingual";
contrastSpec(2).weights = [-1; 1];

%% Initialise SPM and load the estimated model
if ~isfolder(resultsDir)
    error('Results directory does not exist: %s', resultsDir);
end

spmMatFile = fullfile(resultsDir, 'SPM.mat');
if ~isfile(spmMatFile)
    error('SPM.mat was not found: %s', spmMatFile);
end


spm('defaults', 'eeg');
spm_jobman('initcfg');

loadedModel = load(spmMatFile, 'SPM');
if ~isfield(loadedModel, 'SPM')
    error('The selected file does not contain SPM.');
end

SPM = loadedModel.SPM;
if ~(isfield(SPM, 'xVol') && isfield(SPM.xVol, 'S'))
    error('The model has not been estimated. Run Model estimation first.');
end

if ~(isfield(SPM, 'xCon') && ~isempty(SPM.xCon))
    error('No contrasts were found. Define the two directional T-contrasts first.');
end


runStamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outputDir = fullfile(resultsDir, ['publication_report_' runStamp]);
figureDir = fullfile(outputDir, 'figures');
tableDir = fullfile(outputDir, 'tables');
mkdir(outputDir);
mkdir(figureDir);
mkdir(tableDir);

fprintf('\nSPM model: %s\n', spmMatFile);
fprintf('Report folder: %s\n', outputDir);

%% Validate the design and recover subject/group membership
X = double(SPM.xX.X);
if ~(size(X,2) >= 2)
    error('The design matrix has fewer than two columns.');
end

if ~(size(X,1) == study.expectedGroupN(1) + study.expectedGroupN(2))
    error('Expected 43 subjects, but the design contains %d rows.', size(X,1));
end


% The completed two-sample model has the group indicators in columns 1-2.
groupCode = zeros(size(X, 1), 1);
for subjectNumber = 1:size(X, 1)
    subjectDesign = abs(X(subjectNumber, 1:2));
    [~, groupCode(subjectNumber)] = max(subjectDesign);
end
groupN = [sum(groupCode == 1), sum(groupCode == 2)];
if ~isequal(groupN, study.expectedGroupN)
    error('Expected group sizes [%d %d], but the design contains [%d %d].', ...
        study.expectedGroupN(1), study.expectedGroupN(2), groupN(1), groupN(2));
end


inputImages = getInputImages(SPM, resultsDir);
if ~(numel(inputImages) == size(X,1))
    error('Number of input images (%d) differs from design rows (%d).', ...
        numel(inputImages), size(X,1));
end


for subjectNumber = 1:numel(inputImages)
    if ~isfile(stripVolumeIndex(inputImages{subjectNumber}))
        error('Subject image not found: %s', inputImages{subjectNumber});
    end

end

%% Locate the two intended contrasts by their weights
contrastIndices = nan(1, numel(contrastSpec));
for contrastNumber = 1:numel(contrastSpec)
    wanted = contrastSpec(contrastNumber).weights(:);
    matching = [];
    for modelContrast = 1:numel(SPM.xCon)
        if strcmpi(SPM.xCon(modelContrast).STAT, 'T')
            present = full(SPM.xCon(modelContrast).c(:));
            if numel(present) == numel(wanted) && ...
                max(abs(present - wanted)) < 1e-10
                matching(end+1) = modelContrast; %#ok<SAGROW>
            end
        end
    end
    if isempty(matching)
        error('Could not find T-contrast [%s].', num2str(wanted'));
    end

    contrastIndices(contrastNumber) = matching(1);
    if numel(matching) > 1
        warning(['Duplicate contrast [%s] exists at indices %s. ' ...
            'Only the first one (index %d) will be reported.'], ...
            num2str(wanted'), mat2str(matching), matching(1));
    end
end

%% Obtain exact thresholded SPM results and exact SPM tables
originalFolder = pwd;
try


    allPeakTables = cell(1, numel(contrastSpec));
    resultObjects = cell(1, numel(contrastSpec));
    tabObjects = cell(1, numel(contrastSpec));

    for contrastNumber = 1:numel(contrastSpec)
        xSPMinput = struct;
        xSPMinput.swd = resultsDir;
        xSPMinput.title = char(contrastSpec(contrastNumber).name);
        xSPMinput.Ic = contrastIndices(contrastNumber);
        xSPMinput.n = 1;
        xSPMinput.Im = [];
        xSPMinput.pm = [];
        xSPMinput.Ex = [];
        xSPMinput.u = study.voxelFWE;
        xSPMinput.k = study.extentThreshold;
        xSPMinput.thresDesc = 'FWE';

        [~, xSPM] = spm_getSPM(xSPMinput);
        if isempty(xSPM)
            error('SPM could not evaluate contrast %d.', contrastNumber);
        end

        resultObjects{contrastNumber} = xSPM;

        % Inf = retain all local maxima; 8 = minimum 8 mm separation.
        TabDat = spm_list('Table', xSPM, Inf, study.localMaximumDistanceMm);
        tabObjects{contrastNumber} = TabDat;

        exactCsv = fullfile(tableDir, sprintf( ...
            'SPM_exact_contrast_%02d.csv', contrastNumber));
        spm_list('CSVList', TabDat, exactCsv);

        cleanTable = tabDatToTable(TabDat, contrastNumber, ...
            contrastSpec(contrastNumber).name);
        allPeakTables{contrastNumber} = cleanTable;
        writetable(cleanTable, fullfile(tableDir, sprintf( ...
            'clean_peak_table_contrast_%02d.csv', contrastNumber)));
    end

    combinedPeakTable = allPeakTables{1};
    for contrastNumber = 2:numel(allPeakTables)
        combinedPeakTable = [combinedPeakTable; allPeakTables{contrastNumber}];
    end
    writetable(combinedPeakTable, fullfile(tableDir, 'all_contrasts_peak_table.csv'));

    contrastSummary = makeContrastSummary(allPeakTables, contrastSpec, resultObjects);
    writetable(contrastSummary, fullfile(tableDir, 'contrast_summary.csv'));

    %% Save analysis parameters and subject-image inventory
    parameter = [ ...
        "Input condition"; "Conversion"; "Sensor type"; "Time window (ms)"; ...
        "Image dimensions"; "Applied smoothing FWHM (mm, mm, ms)"; ...
        "Second-level design"; "Independence"; "Variance"; "Covariates"; ...
        "ANCOVA"; "Grand mean scaling"; "Global normalisation"; ...
        "Results masking"; "Implicit mask in design"; ...
        "Voxel threshold"; "Extent threshold"; "Group sizes"; ...
        "Residual degrees of freedom"; ...
        "Voxel size (mm, mm, ms)"; ...
        "SPM-estimated residual FWHM (mm, mm, ms)"; ...
        "Search volume (voxels)"; "Search volume (resels)"];

    voxelSize = double(resultObjects{1}.VOX(:)');
    estimatedFWHMmm = double(resultObjects{1}.FWHM(:)') .* voxelSize;
    reselCounts = double(resultObjects{1}.R(:)');

    value = [ ...
        study.condition; study.conversionMode; study.sensorType; ...
        string(mat2str(study.timeWindowMs)); ...
        string(mat2str(study.expectedImageSize)); ...
        string(mat2str(study.appliedSmoothingFWHM)); ...
        "Independent two-sample t-test"; "Yes"; "Unequal"; "None"; ...
        "No"; "No"; "None"; "None"; "Yes"; ...
        "Voxel-level FWE p < 0.05"; "k = 0 voxels"; ...
        sprintf('%s n=%d; %s n=%d', study.groupNames(1), groupN(1), ...
        study.groupNames(2), groupN(2)); ...
        string(resultObjects{1}.df(2)); string(mat2str(voxelSize, 4)); ...
        string(mat2str(estimatedFWHMmm, 4)); ...
        string(resultObjects{1}.S); string(reselCounts(end))];

    analysisParameters = table(parameter, value, ...
        'VariableNames', {'Parameter', 'Value'});
    writetable(analysisParameters, fullfile(tableDir, 'analysis_parameters.csv'));

    subjectNumber = (1:numel(inputImages))';
    group = study.groupNames(groupCode);
    group = group(:);
    imageFile = string(inputImages(:));
    subjectInventory = table(subjectNumber, group, imageFile, ...
        'VariableNames', {'DesignRow', 'Group', 'ImageFile'});
    writetable(subjectInventory, fullfile(tableDir, 'subject_image_inventory.csv'));

    %% Read subject images once for descriptive figures
    [subjectData, inputVolume] = loadSubjectData(inputImages, study.expectedImageSize);

    %% Figure 1: design matrix
    fig = figure('Color', 'w', 'Position', [100 100 920 720]);
    ax = axes(fig);
    displayX = X;
    for columnNumber = 1:size(displayX,2)
        scaleValue = max(abs(displayX(:,columnNumber)));
        if scaleValue > 0
            displayX(:,columnNumber) = displayX(:,columnNumber) ./ scaleValue;
        end
    end
    imagesc(ax, displayX);
    colormap(ax, flipud(gray(256)));
    clim(ax, [-1 1]);
    axis(ax, 'tight');
    xlabel(ax, 'Design-matrix column');
    ylabel(ax, 'Participant');
    title(ax, sprintf('Second-level design: %s (n=%d) vs %s (n=%d)', ...
        study.groupNames(1), groupN(1), study.groupNames(2), groupN(2)), ...
        'FontWeight', 'bold');
    hold(ax, 'on');
    yline(ax, groupN(1) + 0.5, 'Color', [0.85 0.2 0.2], 'LineWidth', 1.5);
    if isfield(SPM.xX, 'name') && numel(SPM.xX.name) == size(X,2)
        xticks(ax, 1:size(X,2));
        xticklabels(ax, cleanLabels(string(SPM.xX.name)));
        xtickangle(ax, 30);
    end
    setPublicationStyle(ax);
    exportFigure(fig, figureDir, 'Figure_1_design_matrix');
    close(fig);

    %% Figure 2: thresholded T maps for both directions
    fig = figure('Color', 'w', 'Position', [100 100 1200 520]);
    layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(layout, 'Voxel-level FWE-corrected sensor-space results', ...
        'FontSize', 15, 'FontWeight', 'bold');

    for contrastNumber = 1:numel(contrastSpec)
        ax = nexttile(layout);
        xSPM = resultObjects{contrastNumber};
        statisticVolume = getStatisticVolume(SPM, contrastIndices(contrastNumber), resultsDir);
        statisticData = spm_read_vols(statisticVolume);

        if ~isempty(allPeakTables{contrastNumber})
            peakWorld = [allPeakTables{contrastNumber}.Xmm(1); ...
                allPeakTables{contrastNumber}.Ymm(1); ...
                allPeakTables{contrastNumber}.TimeMs(1)];
            peakVoxel = worldToVoxel(statisticVolume.mat, peakWorld, size(statisticData));
            sliceNumber = peakVoxel(3);
            displaySlice = statisticData(:,:,sliceNumber);
            displaySlice(displaySlice < xSPM.u) = NaN;
            outlineMask = isfinite(statisticData(:,:,sliceNumber)) & ...
                statisticData(:,:,sliceNumber) ~= 0;
            drawSensorSlice(ax, displaySlice, statisticVolume, sliceNumber, ...
                parula(256), outlineMask);
            hold(ax, 'on');
            plot(ax, peakWorld(1), peakWorld(2), 'wo', ...
                'MarkerFaceColor', [0.85 0.15 0.15], 'MarkerSize', 7, ...
                'LineWidth', 1.2);
            colourBar = colorbar(ax);
            colourBar.Label.String = 'T statistic';
            subtitleText = sprintf('Peak %.0f ms | T=%.2f | p_{FWE}=%.3f', ...
                peakWorld(3), allPeakTables{contrastNumber}.T(1), ...
                allPeakTables{contrastNumber}.PeakPFWE(1));
        else
            [~, linearMaximum] = max(statisticData(:));
            [~, ~, sliceNumber] = ind2sub(size(statisticData), linearMaximum);
            emptySlice = statisticData(:,:,sliceNumber);
            emptySlice(:) = NaN;
            outlineMask = isfinite(statisticData(:,:,sliceNumber)) & ...
                statisticData(:,:,sliceNumber) ~= 0;
            drawSensorSlice(ax, emptySlice, statisticVolume, sliceNumber, ...
                parula(256), outlineMask);
            text(ax, 0.5, 0.5, 'No suprathreshold voxels', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'FontWeight', 'bold', 'FontSize', 13, 'Color', [0.25 0.25 0.25]);
            subtitleText = 'Voxel-level FWE p < .05, k = 0';
        end

        title(ax, contrastSpec(contrastNumber).name, 'FontWeight', 'bold');
        subtitle(ax, subtitleText);
        xlabel(ax, 'Sensor-image x (mm)');
        ylabel(ax, 'Sensor-image y (mm)');
        setPublicationStyle(ax);
    end

    exportFigure(fig, figureDir, 'Figure_2_FWE_thresholded_T_maps');
    close(fig);

    %% Figures 3-4 and descriptive peak table (only if contrast 1 survives)
    descriptiveStats = table();
    if ~isempty(allPeakTables{1})
        primaryPeak = [allPeakTables{1}.Xmm(1); ...
            allPeakTables{1}.Ymm(1); ...
            allPeakTables{1}.TimeMs(1)];
        peakVoxel = worldToVoxel(inputVolume.mat, primaryPeak, size(subjectData(:,:,:,1)));
        peakSlice = peakVoxel(3);

        group1Mean = mean(subjectData(:,:,:,groupCode == 1), 4, 'omitnan');
        group2Mean = mean(subjectData(:,:,:,groupCode == 2), 4, 'omitnan');
        map1 = group1Mean(:,:,peakSlice);
        map2 = group2Mean(:,:,peakSlice);
        differenceMap = map1 - map2;

        validMask = any(isfinite(subjectData(:,:,peakSlice,:)) & ...
            subjectData(:,:,peakSlice,:) ~= 0, 4);
        map1(~validMask) = NaN;
        map2(~validMask) = NaN;
        differenceMap(~validMask) = NaN;

        groupLimits = finiteLimits([map1(:); map2(:)], false);
        differenceLimits = finiteLimits(differenceMap(:), true);

        fig = figure('Color', 'w', 'Position', [100 100 1450 500]);
        layout = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
        title(layout, sprintf('Descriptive sensor maps at %.0f ms', primaryPeak(3)), ...
            'FontSize', 15, 'FontWeight', 'bold');

        ax1 = nexttile(layout);
        drawSensorSlice(ax1, map1, inputVolume, peakSlice, parula(256), validMask);
        clim(ax1, groupLimits);
        title(ax1, sprintf('%s (n=%d)', study.groupNames(1), groupN(1)));
        colourBar1 = colorbar(ax1);
        colourBar1.Label.String = 'Model estimate (a.u.)';

        ax2 = nexttile(layout);
        drawSensorSlice(ax2, map2, inputVolume, peakSlice, parula(256), validMask);
        clim(ax2, groupLimits);
        title(ax2, sprintf('%s (n=%d)', study.groupNames(2), groupN(2)));
        colourBar2 = colorbar(ax2);
        colourBar2.Label.String = 'Model estimate (a.u.)';

        ax3 = nexttile(layout);
        drawSensorSlice(ax3, differenceMap, inputVolume, peakSlice, ...
            divergingMap(256), validMask);
        clim(ax3, differenceLimits);
        title(ax3, 'Monolingual - Bilingual');
        colourBar3 = colorbar(ax3);
        colourBar3.Label.String = 'Difference (a.u.)';

        axesList = [ax1 ax2 ax3];
        for oneAxis = axesList
            hold(oneAxis, 'on');
            plot(oneAxis, primaryPeak(1), primaryPeak(2), 'ko', ...
                'MarkerFaceColor', 'w', 'MarkerSize', 6, 'LineWidth', 1.1);
            xlabel(oneAxis, 'Sensor-image x (mm)');
            ylabel(oneAxis, 'Sensor-image y (mm)');
            setPublicationStyle(oneAxis);
        end

        exportFigure(fig, figureDir, 'Figure_3_group_maps_at_significant_latency');
        close(fig);

        % Descriptive time course at the inferentially selected sensor pixel.
        timeMs = volumeTimeAxis(inputVolume, size(subjectData,3), peakVoxel(1:2));
        subjectTimeCourses = squeeze(subjectData(peakVoxel(1), peakVoxel(2), :, :));
        if isvector(subjectTimeCourses)
            subjectTimeCourses = subjectTimeCourses(:);
        end

        group1Time = subjectTimeCourses(:, groupCode == 1);
        group2Time = subjectTimeCourses(:, groupCode == 2);
        mean1 = mean(group1Time, 2, 'omitnan');
        mean2 = mean(group2Time, 2, 'omitnan');
        ci1 = 1.96 .* std(group1Time, 0, 2, 'omitnan') ./ sqrt(groupN(1));
        ci2 = 1.96 .* std(group2Time, 0, 2, 'omitnan') ./ sqrt(groupN(2));

        peakValues = squeeze(subjectData(peakVoxel(1), peakVoxel(2), peakSlice, :));
        peakValues = peakValues(:);
        descriptiveStats = makeDescriptivePeakTable(peakValues, groupCode, ...
            study.groupNames, primaryPeak);
        writetable(descriptiveStats, fullfile(tableDir, ...
            'descriptive_values_at_selected_peak.csv'));

        fig = figure('Color', 'w', 'Position', [100 100 1400 560]);
        layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        % Reserve a separate strip below the plots for the descriptive note so
        % it cannot overlap the x-axis labels.
        layout.OuterPosition = [0.03 0.11 0.94 0.87];
        title(layout, 'Descriptive follow-up at the inferentially selected peak', ...
            'FontSize', 15, 'FontWeight', 'bold');

        monoColor = [0.85 0.37 0.12];
        biColor = [0.10 0.45 0.75];

        ax = nexttile(layout);
        hold(ax, 'on');
        shadedError(ax, timeMs, mean1, ci1, monoColor);
        shadedError(ax, timeMs, mean2, ci2, biColor);
        xline(ax, primaryPeak(3), '--k', sprintf('peak %.0f ms', primaryPeak(3)), ...
            'LabelVerticalAlignment', 'bottom');
        yline(ax, 0, ':', 'Color', [0.45 0.45 0.45]);
        xlim(ax, study.timeWindowMs);
        xlabel(ax, 'Latency (ms)');
        ylabel(ax, 'Model estimate (a.u.)');
        title(ax, sprintf('Sensor-image location [%.0f, %.0f] mm', ...
            primaryPeak(1), primaryPeak(2)));
        legend(ax, study.groupNames, 'Location', 'best', 'Box', 'off');
        setPublicationStyle(ax);

        ax = nexttile(layout);
        hold(ax, 'on');
        rng(2026, 'twister');
        values1 = peakValues(groupCode == 1);
        values2 = peakValues(groupCode == 2);
        boxchart(ax, ones(size(values1)), values1, ...
            'BoxFaceColor', monoColor, 'MarkerStyle', 'none');
        boxchart(ax, 2 .* ones(size(values2)), values2, ...
            'BoxFaceColor', biColor, 'MarkerStyle', 'none');
        scatter(ax, 1 + 0.16 .* (rand(size(values1)) - 0.5), values1, 30, ...
            monoColor, 'filled', 'MarkerFaceAlpha', 0.75, 'MarkerEdgeColor', 'w');
        scatter(ax, 2 + 0.16 .* (rand(size(values2)) - 0.5), values2, 30, ...
            biColor, 'filled', 'MarkerFaceAlpha', 0.75, 'MarkerEdgeColor', 'w');
        xlim(ax, [0.5 2.5]);
        xticks(ax, [1 2]);
        xticklabels(ax, study.groupNames);
        ylabel(ax, 'Model estimate (a.u.)');
        title(ax, sprintf('Participant values at %.0f ms', primaryPeak(3)));
        setPublicationStyle(ax);

        annotation(fig, 'textbox', [0.10 0.012 0.80 0.035], ...
            'String', ['Descriptive only: the location and latency were selected ' ...
            'from the same group contrast (not an independent ROI).'], ...
            'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontSize', 9, ...
            'FontAngle', 'italic', 'Color', [0.3 0.3 0.3]);

        exportFigure(fig, figureDir, 'Figure_4_peak_timecourse_and_distribution');
        close(fig);
    end

    %% Write a manuscript-ready Methods/Results draft and a reporting checklist
    writeReportDraft(fullfile(outputDir, 'Methods_and_Results_draft.md'), ...
        study, groupN, contrastSpec, allPeakTables, contrastSummary, ...
        resultObjects, SPM);

    writeReadme(fullfile(outputDir, 'README_reporting_checklist.txt'));

    wordTableFile = fullfile(outputDir, ...
        'Sensor_space_tables_for_Word.html');
    writeWordCompatibleTables(wordTableFile, analysisParameters, ...
        allPeakTables, contrastSpec, resultObjects, descriptiveStats, ...
        study, groupN);

    fprintf('\n========== PUBLICATION REPORT COMPLETE ==========\n');
    fprintf('Tables: %s\n', tableDir);
    fprintf('Figures: %s\n', figureDir);
    fprintf('Draft: %s\n', fullfile(outputDir, 'Methods_and_Results_draft.md'));
    fprintf('Editable Word tables: %s\n', wordTableFile);
    fprintf(['\nNOTE: x/y are sensor-image coordinates; the third coordinate is ' ...
        'latency in ms. They are not MNI coordinates.\n']);

    try
        load handel.mat;
        sound(y, Fs);
    catch
    beep;
    end


    %% =========================== FUNCTIONS ================================

catch cleanupError
    cd(originalFolder);
    rethrow(cleanupError);
end
cd(originalFolder);
function inputImages = getInputImages(SPM, resultsDir)
    if ~(isfield(SPM, 'xY') && isfield(SPM.xY, 'P'))
        error('SPM.xY.P (subject input images) is missing.');
    end


    if ischar(SPM.xY.P)
        inputImages = cellstr(SPM.xY.P);
    elseif iscell(SPM.xY.P)
        inputImages = SPM.xY.P(:);
    else
        inputImages = cellstr(string(SPM.xY.P));
    end

    for i = 1:numel(inputImages)
        onePath = strtrim(char(inputImages{i}));
        volumeSuffix = regexp(onePath, ',\d+$', 'match', 'once');
        pathWithoutSuffix = regexprep(onePath, ',\d+$', '');
        if isempty(volumeSuffix)
            volumeSuffix = '';
        end
        if ~isfile(pathWithoutSuffix)
            candidate = fullfile(resultsDir, pathWithoutSuffix);
            if isfile(candidate)
                onePath = [candidate volumeSuffix];
            end
        end
        inputImages{i} = onePath;
    end
end


function cleanPath = stripVolumeIndex(filePath)
    cleanPath = regexprep(char(filePath), ',\d+$', '');
end


function labels = cleanLabels(labels)
    labels = regexprep(labels, '^Sn\(\d+\)\s*', '');
    labels = strrep(labels, '_', ' ');
end


function V = getStatisticVolume(SPM, contrastIndex, resultsDir)
    V = SPM.xCon(contrastIndex).Vspm;
    if numel(V) > 1
        V = V(1);
    end
    if isstruct(V) && isfield(V, 'fname')
        statisticFile = V.fname;
    else
        statisticFile = char(V);
    end
    if ~isfile(stripVolumeIndex(statisticFile))
        statisticFile = fullfile(resultsDir, statisticFile);
    end
    V = spm_vol(statisticFile);
    if numel(V) > 1
        V = V(1);
    end
end


function cleanTable = tabDatToTable(TabDat, contrastIndex, contrastName)
    variableNames = {'ContrastIndex','Contrast','ClusterNumber','SetPFWE', ...
        'NumberClusters','ClusterPFWE','ClusterPFDR','ExtentVoxels', ...
        'ClusterPUncorrected','PeakPFWE','PeakPFDR','T','Z', ...
        'PeakPUncorrected','Xmm','Ymm','TimeMs'};

    if isempty(TabDat.dat)
        cleanTable = table('Size', [0 numel(variableNames)], ...
            'VariableTypes', ["double","string",repmat("double",1,15)], ...
            'VariableNames', variableNames);
        return;
    end

    numberOfRows = size(TabDat.dat, 1);
    contrastColumn = repmat(string(contrastName), numberOfRows, 1);
    contrastIndexColumn = repmat(double(contrastIndex), numberOfRows, 1);
    numericData = nan(numberOfRows, 15);
    clusterNumber = 0;
    lastClusterStats = nan(1,4);

    for rowNumber = 1:numberOfRows
    % Columns in the official SPM TabDat structure:
    % 1 set-p, 2 number clusters, 3 cluster pFWE, 4 cluster pFDR,
    % 5 extent, 6 cluster punc, 7 peak pFWE, 8 peak pFDR,
    % 9 T, 10 Z, 11 peak punc, 12 [x y z/time].
        setP = cellNumber(TabDat.dat{rowNumber,1});
        numberClusters = cellNumber(TabDat.dat{rowNumber,2});
        clusterPFWE = cellNumber(TabDat.dat{rowNumber,3});
        clusterPFDR = cellNumber(TabDat.dat{rowNumber,4});
        extentVoxels = cellNumber(TabDat.dat{rowNumber,5});
        clusterPUncorrected = cellNumber(TabDat.dat{rowNumber,6});

        if isfinite(clusterPFWE) || isfinite(extentVoxels)
            clusterNumber = clusterNumber + 1;
            lastClusterStats = [clusterPFWE, clusterPFDR, ...
                extentVoxels, clusterPUncorrected];
        else
            clusterPFWE = lastClusterStats(1);
            clusterPFDR = lastClusterStats(2);
            extentVoxels = lastClusterStats(3);
            clusterPUncorrected = lastClusterStats(4);
        end

        coordinates = TabDat.dat{rowNumber,12};
        if isempty(coordinates)
            coordinates = [NaN; NaN; NaN];
        end
        coordinates = double(coordinates(:));
        if numel(coordinates) < 3
            coordinates(end+1:3) = NaN;
        end

        numericData(rowNumber,:) = [clusterNumber, setP, numberClusters, ...
            clusterPFWE, clusterPFDR, extentVoxels, clusterPUncorrected, ...
            cellNumber(TabDat.dat{rowNumber,7}), ...
            cellNumber(TabDat.dat{rowNumber,8}), ...
            cellNumber(TabDat.dat{rowNumber,9}), ...
            cellNumber(TabDat.dat{rowNumber,10}), ...
            cellNumber(TabDat.dat{rowNumber,11}), ...
            coordinates(1), coordinates(2), coordinates(3)];
    end

    cleanTable = table(contrastIndexColumn, contrastColumn, ...
        numericData(:,1), numericData(:,2), numericData(:,3), ...
        numericData(:,4), numericData(:,5), numericData(:,6), ...
        numericData(:,7), numericData(:,8), numericData(:,9), ...
        numericData(:,10), numericData(:,11), numericData(:,12), ...
        numericData(:,13), numericData(:,14), numericData(:,15), ...
        'VariableNames', variableNames);
end


function numberValue = cellNumber(value)
    if isempty(value) || ~isnumeric(value)
        numberValue = NaN;
    else
        numberValue = double(value(1));
    end
end


function summaryTable = makeContrastSummary(peakTables, contrastSpec, resultObjects)
    numberOfContrasts = numel(contrastSpec);
    contrast = strings(numberOfContrasts,1);
    survivingClusters = zeros(numberOfContrasts,1);
    reportedMaxima = zeros(numberOfContrasts,1);
    thresholdT = nan(numberOfContrasts,1);
    bestPeakPFWE = nan(numberOfContrasts,1);
    maximumT = nan(numberOfContrasts,1);
    xMm = nan(numberOfContrasts,1);
    yMm = nan(numberOfContrasts,1);
    timeMs = nan(numberOfContrasts,1);
    largestClusterVoxels = nan(numberOfContrasts,1);

    for i = 1:numberOfContrasts
        contrast(i) = contrastSpec(i).name;
        thresholdT(i) = resultObjects{i}.u;
        oneTable = peakTables{i};
        if ~isempty(oneTable)
            survivingClusters(i) = numel(unique(oneTable.ClusterNumber));
            reportedMaxima(i) = height(oneTable);
            [bestPeakPFWE(i), bestRow] = min(oneTable.PeakPFWE);
            maximumT(i) = oneTable.T(bestRow);
            xMm(i) = oneTable.Xmm(bestRow);
            yMm(i) = oneTable.Ymm(bestRow);
            timeMs(i) = oneTable.TimeMs(bestRow);
            largestClusterVoxels(i) = max(oneTable.ExtentVoxels);
        end
    end

    summaryTable = table(contrast, survivingClusters, reportedMaxima, ...
        thresholdT, bestPeakPFWE, maximumT, xMm, yMm, timeMs, ...
        largestClusterVoxels, ...
        'VariableNames', {'Contrast','SurvivingClusters','ReportedMaxima', ...
        'FWEThresholdT','BestPeakPFWE','MaximumT','Xmm','Ymm','TimeMs', ...
        'LargestClusterVoxels'});
end


function [allData, referenceVolume] = loadSubjectData(inputImages, expectedSize)
    numberOfSubjects = numel(inputImages);
    referenceVolume = spm_vol(inputImages{1});
    if numel(referenceVolume) > 1
        referenceVolume = referenceVolume(1);
    end
    firstData = spm_read_vols(referenceVolume);
    if ~isequal(size(firstData), expectedSize)
        error('Expected image size %s, but found %s.', ...
            mat2str(expectedSize), mat2str(size(firstData)));
    end


    allData = nan([size(firstData), numberOfSubjects], 'double');
    allData(:,:,:,1) = firstData;

    fprintf('\nReading %d subject images for descriptive figures...\n', numberOfSubjects);
    for subjectNumber = 2:numberOfSubjects
        V = spm_vol(inputImages{subjectNumber});
        if numel(V) > 1
            V = V(1);
        end
        if ~isequal(V.dim, referenceVolume.dim)
            error('Image dimensions differ for subject image %d.', subjectNumber);
        end

        if ~(max(abs(V.mat(:) - referenceVolume.mat(:))) < 1e-5)
            error('Image affine differs for subject image %d.', subjectNumber);
        end

        allData(:,:,:,subjectNumber) = spm_read_vols(V);
    end
end


function voxel = worldToVoxel(affineMatrix, world, imageSize)
    voxelHomogeneous = affineMatrix \ [double(world(:)); 1];
    voxel = round(voxelHomogeneous(1:3));
    voxel = max(voxel, [1;1;1]);
    voxel = min(voxel, double(imageSize(1:3))');
end


function drawSensorSlice(ax, sliceData, V, sliceNumber, colorMap, outlineMask)
    [xAxis, yAxis] = sliceSpatialAxes(V, sliceNumber);
    imageHandle = imagesc(ax, xAxis, yAxis, sliceData');
    set(imageHandle, 'AlphaData', isfinite(sliceData'));
    axis(ax, 'xy');
    axis(ax, 'image');
    colormap(ax, colorMap);
    box(ax, 'off');

    if nargin < 6 || isempty(outlineMask)
        outlineMask = isfinite(sliceData) & sliceData ~= 0;
    end
    if any(outlineMask(:))
        hold(ax, 'on');
        contour(ax, xAxis, yAxis, double(outlineMask'), [0.5 0.5], ...
            'Color', [0.2 0.2 0.2], 'LineWidth', 0.8);
    end
end


function [xAxis, yAxis] = sliceSpatialAxes(V, sliceNumber)
    nx = V.dim(1);
    ny = V.dim(2);
    xAxis = nan(1,nx);
    yAxis = nan(1,ny);
    for i = 1:nx
        world = V.mat * [i; 1; sliceNumber; 1];
        xAxis(i) = world(1);
    end
    for j = 1:ny
        world = V.mat * [1; j; sliceNumber; 1];
        yAxis(j) = world(2);
    end
end


function timeMs = volumeTimeAxis(V, numberOfSlices, fixedXY)
    timeMs = nan(numberOfSlices,1);
    for k = 1:numberOfSlices
        world = V.mat * [fixedXY(1); fixedXY(2); k; 1];
        timeMs(k) = world(3);
    end
end


function limits = finiteLimits(values, symmetric)
    values = values(isfinite(values));
    if isempty(values)
        limits = [-1 1];
        return;
    end
    if symmetric
        maximum = max(abs(values));
        if maximum == 0
            maximum = 1;
        end
        limits = [-maximum maximum];
    else
        limits = [min(values) max(values)];
        if limits(1) == limits(2)
            limits = limits + [-0.5 0.5];
        end
    end
end


function map = divergingMap(numberOfColors)
    anchors = [0.13 0.40 0.67; 0.33 0.66 0.82; 0.82 0.90 0.94; ...
        1.00 1.00 1.00; 0.99 0.78 0.57; 0.88 0.40 0.29; ...
        0.70 0.09 0.17];
    anchorPosition = linspace(0,1,size(anchors,1));
    queryPosition = linspace(0,1,numberOfColors);
    map = interp1(anchorPosition, anchors, queryPosition, 'linear');
    map = min(max(map,0),1);
end


function shadedError(ax, x, meanValue, errorValue, colorValue)
    x = x(:);
    meanValue = meanValue(:);
    errorValue = errorValue(:);
    valid = isfinite(x) & isfinite(meanValue) & isfinite(errorValue);
    x = x(valid);
    meanValue = meanValue(valid);
    errorValue = errorValue(valid);
    fill(ax, [x; flipud(x)], ...
        [meanValue-errorValue; flipud(meanValue+errorValue)], ...
        colorValue, 'FaceAlpha', 0.18, 'EdgeColor', 'none', ...
        'HandleVisibility', 'off');
    plot(ax, x, meanValue, 'Color', colorValue, 'LineWidth', 2.1);
end


function descriptiveTable = makeDescriptivePeakTable(values, groupCode, groupNames, peak)
    values1 = values(groupCode == 1);
    values2 = values(groupCode == 2);
    n1 = sum(isfinite(values1));
    n2 = sum(isfinite(values2));
    m1 = mean(values1, 'omitnan');
    m2 = mean(values2, 'omitnan');
    s1 = std(values1, 0, 'omitnan');
    s2 = std(values2, 0, 'omitnan');
    difference = m1 - m2;
    standardError = sqrt(s1^2/n1 + s2^2/n2);
    welchDf = (s1^2/n1 + s2^2/n2)^2 / ...
        ((s1^2/n1)^2/(n1-1) + (s2^2/n2)^2/(n2-1));

    if exist('tinv', 'file') == 2
        criticalT = tinv(0.975, welchDf);
    else
        criticalT = 1.96;
    end
    ciLower = difference - criticalT * standardError;
    ciUpper = difference + criticalT * standardError;

    pooledSD = sqrt(((n1-1)*s1^2 + (n2-1)*s2^2) / (n1+n2-2));
    cohensD = difference / pooledSD;
    smallSampleCorrection = 1 - 3/(4*(n1+n2)-9);
    hedgesG = smallSampleCorrection * cohensD;

    descriptiveTable = table(groupNames(1), n1, m1, s1, ...
        groupNames(2), n2, m2, s2, difference, ciLower, ciUpper, ...
        welchDf, cohensD, hedgesG, peak(1), peak(2), peak(3), ...
        'VariableNames', {'Group1','N1','Mean1','SD1','Group2','N2', ...
        'Mean2','SD2','MeanDifference','DifferenceCI95Lower', ...
        'DifferenceCI95Upper','WelchDf','CohensD','HedgesG', ...
        'Xmm','Ymm','TimeMs'});
end


function setPublicationStyle(ax)
    set(ax, 'FontName', 'Arial', 'FontSize', 11, 'LineWidth', 1, ...
        'TickDir', 'out', 'Box', 'off', 'Color', 'w');
end


function exportFigure(fig, folderName, baseName)
    pngFile = fullfile(folderName, [baseName '.png']);
    pdfFile = fullfile(folderName, [baseName '.pdf']);
    exportgraphics(fig, pngFile, 'Resolution', 600, 'BackgroundColor', 'white');
    exportgraphics(fig, pdfFile, 'ContentType', 'vector', 'BackgroundColor', 'white');
end


function writeReportDraft(fileName, study, groupN, contrastSpec, ...
    peakTables, summaryTable, resultObjects, SPM)
    fid = fopen(fileName, 'w');
    if ~(fid ~= -1)
        error('Could not create report draft: %s', fileName);
    end

    try


        fprintf(fid, '# Sensor-space statistical analysis\n\n');
        fprintf(fid, '## Methods (manuscript-ready draft)\n\n');
        fprintf(fid, ['Convolution-model estimates for the `%s` condition were ' ...
            'converted to three-dimensional scalp-by-scalp-by-time images ' ...
            '(%d x %d x %d; %d-%d ms) using the EEG sensor modality. Images ' ...
            'were smoothed with a [%d %d %d] mm/mm/ms FWHM Gaussian kernel. ' ...
            'At the second level, an independent two-sample t-test compared ' ...
            '%d monolingual and %d bilingual participants. Independence was ' ...
            'assumed and unequal variances were modelled. No covariates, ANCOVA, ' ...
            'grand-mean scaling, global normalisation, explicit mask, or results ' ...
            'masking were used; implicit masking was enabled in the design. ' ...
            'Directional t-contrasts tested monolingual > bilingual [1 -1] and ' ...
            'bilingual > monolingual [-1 1]. Statistical significance was ' ...
            'assessed across the full scalp-time search volume using voxel-level ' ...
            'family-wise error correction at p < .05 with an extent threshold ' ...
            'of k = 0 voxels.\n\n'], ...
            study.condition, study.expectedImageSize, study.timeWindowMs, ...
            study.appliedSmoothingFWHM, groupN(1), groupN(2));

        fprintf(fid, '## Results (manuscript-ready draft)\n\n');
        for i = 1:numel(contrastSpec)
            oneTable = peakTables{i};
            if isempty(oneTable)
                fprintf(fid, ['For **%s**, no sensor-space voxels survived ' ...
                    'voxel-level FWE correction (p < .05; k = 0).\n\n'], ...
                    contrastSpec(i).name);
            else
                [~, bestRow] = min(oneTable.PeakPFWE);
                fprintf(fid, ['For **%s**, %d cluster(s) survived the voxel-height ' ...
                    'threshold. The strongest peak occurred at sensor-image ' ...
                    'coordinates x = %.0f mm and y = %.0f mm at %.0f ms, ' ...
                    'T(%g) = %.2f, Z = %.2f, voxel/peak-level p_FWE = %.3f, ' ...
                    'cluster extent k = %.0f voxels, cluster-level p_FWE = %.3f. ' ...
                    'The x-y coordinates describe the two-dimensional sensor ' ...
                    'image and must not be interpreted as MNI or source-space ' ...
                    'coordinates.\n\n'], ...
                    contrastSpec(i).name, ...
                    numel(unique(oneTable.ClusterNumber)), ...
                    oneTable.Xmm(bestRow), oneTable.Ymm(bestRow), ...
                    oneTable.TimeMs(bestRow), resultObjects{i}.df(2), ...
                    oneTable.T(bestRow), oneTable.Z(bestRow), ...
                    oneTable.PeakPFWE(bestRow), ...
                    oneTable.ExtentVoxels(bestRow), ...
                    oneTable.ClusterPFWE(bestRow));
            end
        end

        fprintf(fid, '## Required tables and figures\n\n');
        fprintf(fid, ['- Report `analysis_parameters.csv` in Methods.\n' ...
            '- Report `contrast_summary.csv` and `all_contrasts_peak_table.csv` ' ...
            'as the inferential results.\n' ...
            '- Use Figure 2 as the primary inferential figure.\n' ...
            '- Use Figures 3-4 only as descriptive visualisations.\n' ...
            '- Keep the null reverse contrast in the text; do not omit it.\n' ...
            '- State explicitly that x/y are sensor-image coordinates and z is ' ...
            'latency in milliseconds.\n\n']);

        fprintf(fid, '## Model metadata copied from SPM.mat\n\n');
        fprintf(fid, '- Residual degrees of freedom: %.1f\n', SPM.xX.erdf);
        if isfield(SPM.xVol, 'FWHM')
            fprintf(fid, '- Estimated residual smoothness (voxels): `%s`\n', ...
                mat2str(double(SPM.xVol.FWHM), 4));
        end
        if isfield(SPM.xVol, 'R')
            fprintf(fid, '- Search-volume resels: `%s`\n', ...
                mat2str(double(SPM.xVol.R), 4));
        end
        fprintf(fid, '\n');

        fprintf(fid, '## Interpretation boundary\n\n');
        fprintf(fid, ['The inferential claim is a localised sensor-space difference ' ...
            'at the reported latency. It is not evidence for a specific cortical ' ...
            'generator. Cluster-level significance should not be claimed when ' ...
            'the cluster-level FWE p-value exceeds .05. Peak-extracted group ' ...
            'plots and effect sizes are post-selection descriptions, not ' ...
            'independent confirmatory tests.\n']);

        % Suppress an unused-variable warning while keeping the summary available
        % to the caller and documenting that it was produced.
        if ~(height(summaryTable) == numel(contrastSpec))
            error('A required check failed.');
        end


    catch cleanupError
        fclose(fid);
        rethrow(cleanupError);
    end
    fclose(fid);
end


function writeWordCompatibleTables(fileName, analysisParameters, ...
    peakTables, contrastSpec, resultObjects, descriptiveStats, study, groupN)
% Write editable HTML tables. Microsoft Word opens this file directly;
% the tables can then be copied into the thesis or saved as DOCX.

    fid = fopen(fileName, 'w', 'n', 'UTF-8');
    if ~(fid ~= -1)
        error('Could not create Word-compatible table file: %s', fileName);
    end

    try


        fprintf(fid, ['<!DOCTYPE html>\n<html>\n<head>\n' ...
            '<meta charset="UTF-8">\n' ...
            '<title>Sensor-space thesis tables</title>\n' ...
            '<style>\n' ...
            '@page { size: A4 landscape; margin: 1.5cm; }\n' ...
            'body { font-family: "Times New Roman", serif; font-size: 11pt; ' ...
            'color: #111; line-height: 1.25; }\n' ...
            '.placement { font-family: Arial, sans-serif; font-size: 9.5pt; ' ...
            'color: #555; margin-bottom: 5pt; }\n' ...
            '.caption { font-weight: bold; margin: 0 0 7pt 0; }\n' ...
            'table { border-collapse: collapse; width: 100%%; margin-bottom: 7pt; }\n' ...
            'th { background: #E7EEF7; font-weight: bold; text-align: center; }\n' ...
            'th, td { border: 0.7pt solid #555; padding: 5pt 6pt; ' ...
            'vertical-align: middle; }\n' ...
            'td:first-child { text-align: left; }\n' ...
            'td { text-align: center; }\n' ...
            '.note { font-size: 9.5pt; margin-top: 4pt; }\n' ...
            '.pagebreak { page-break-before: always; }\n' ...
            '.nowrap { white-space: nowrap; }\n' ...
            '</style>\n</head>\n<body>\n']);

        %% Methods table
        fprintf(fid, '<div class="placement">Suggested placement: Methods section</div>\n');
        fprintf(fid, '<div class="caption">Sensor-space image construction and second-level analysis parameters</div>\n');
        fprintf(fid, '<table>\n<tr><th style="width:42%%">Analysis component</th><th>Specification</th></tr>\n');

        for rowNumber = 1:height(analysisParameters)
            fprintf(fid, '<tr><td>%s</td><td>%s</td></tr>\n', ...
                htmlEscape(analysisParameters.Parameter(rowNumber)), ...
                htmlEscape(analysisParameters.Value(rowNumber)));
        end

        fprintf(fid, '</table>\n');
        fprintf(fid, ['<p class="note"><b>Note.</b> FWHM = full width at half ' ...
            'maximum; FWE = family-wise error. The applied smoothing kernel ' ...
            '(%s mm/mm/ms) and the residual smoothness estimated by SPM are ' ...
            'different quantities and should be reported separately. The first ' ...
            'two dimensions describe the two-dimensional sensor image; the third ' ...
            'dimension represents latency.</p>\n'], ...
            htmlEscape(string(mat2str(study.appliedSmoothingFWHM))));

        %% Inferential Results table
        fprintf(fid, '<div class="pagebreak"></div>\n');
        fprintf(fid, '<div class="placement">Suggested placement: Results section</div>\n');
        fprintf(fid, '<div class="caption">FWE-corrected sensor-space comparison of monolingual and bilingual groups</div>\n');
        fprintf(fid, ['<table>\n<tr>' ...
            '<th>Contrast</th><th>Outcome</th><th class="nowrap"><i>T</i>(df)</th>' ...
            '<th><i>Z</i></th><th class="nowrap"><i>p</i><sub>FWE</sub><br>(peak)</th>' ...
            '<th><i>k</i><br>(voxels)</th>' ...
            '<th class="nowrap"><i>p</i><sub>FWE</sub><br>(cluster)</th>' ...
            '<th>x<br>(mm)</th><th>y<br>(mm)</th><th>Latency<br>(ms)</th>' ...
            '</tr>\n']);

        for contrastNumber = 1:numel(contrastSpec)
            oneTable = peakTables{contrastNumber};
            if isempty(oneTable)
                fprintf(fid, ['<tr><td>%s</td>' ...
                    '<td>No suprathreshold voxels</td>' ...
                    '<td>&mdash;</td><td>&mdash;</td><td>&mdash;</td>' ...
                    '<td>0</td><td>&mdash;</td><td>&mdash;</td>' ...
                    '<td>&mdash;</td><td>&mdash;</td></tr>\n'], ...
                    htmlEscape(contrastSpec(contrastNumber).name));
            else
                for peakRow = 1:height(oneTable)
                    if peakRow == 1
                        outcomeText = 'Significant peak';
                    else
                        outcomeText = 'Additional local maximum';
                    end
                    fprintf(fid, ['<tr><td>%s</td><td>%s</td>' ...
                        '<td>%.2f (%.0f)</td><td>%.2f</td><td>%s</td>' ...
                        '<td>%.0f</td><td>%s</td><td>%.0f</td><td>%.0f</td>' ...
                        '<td>%.0f</td></tr>\n'], ...
                        htmlEscape(contrastSpec(contrastNumber).name), ...
                        outcomeText, oneTable.T(peakRow), ...
                        resultObjects{contrastNumber}.df(2), ...
                        oneTable.Z(peakRow), ...
                        pValueText(oneTable.PeakPFWE(peakRow)), ...
                        oneTable.ExtentVoxels(peakRow), ...
                        pValueText(oneTable.ClusterPFWE(peakRow)), ...
                        oneTable.Xmm(peakRow), oneTable.Ymm(peakRow), ...
                        oneTable.TimeMs(peakRow));
                end
            end
        end

        fprintf(fid, '</table>\n');
        fprintf(fid, ['<p class="note"><b>Note.</b> Group sizes were ' ...
            '%s <i>n</i> = %d and %s <i>n</i> = %d. Results were thresholded ' ...
            'at voxel-level <i>p</i><sub>FWE</sub> &lt; .05 across the full ' ...
            'scalp-time search volume with an extent threshold of <i>k</i> = 0. ' ...
            '<i>k</i> is the cluster extent in voxels. x and y are coordinates ' ...
            'of the two-dimensional sensor image and are not MNI coordinates; ' ...
            'latency is expressed in milliseconds. Peak-level and cluster-level ' ...
            '<i>p</i><sub>FWE</sub> values represent different inferences.</p>\n'], ...
            htmlEscape(study.groupNames(1)), groupN(1), ...
            htmlEscape(study.groupNames(2)), groupN(2));

        %% Descriptive peak table
        if ~isempty(descriptiveStats)
            fprintf(fid, '<div class="pagebreak"></div>\n');
            fprintf(fid, ['<div class="placement">Suggested placement: Results ' ...
                'section after the inferential table, or Appendix</div>\n']);
            fprintf(fid, '<div class="caption">Descriptive group estimates at the FWE-significant sensor-space peak</div>\n');
            fprintf(fid, ['<table>\n<tr>' ...
                '<th>x<br>(mm)</th><th>y<br>(mm)</th><th>Latency<br>(ms)</th>' ...
                '<th>%s<br><i>n</i></th><th>%s<br>Mean</th><th>%s<br>SD</th>' ...
                '<th>%s<br><i>n</i></th><th>%s<br>Mean</th><th>%s<br>SD</th>' ...
                '<th>Mean difference<br>(%s &minus; %s)</th>' ...
                '<th>95%% CI of<br>difference</th><th>Hedges'' <i>g</i></th>' ...
                '</tr>\n'], ...
                htmlEscape(study.groupNames(1)), htmlEscape(study.groupNames(1)), ...
                htmlEscape(study.groupNames(1)), htmlEscape(study.groupNames(2)), ...
                htmlEscape(study.groupNames(2)), htmlEscape(study.groupNames(2)), ...
                htmlEscape(study.groupNames(1)), htmlEscape(study.groupNames(2)));

            fprintf(fid, ['<tr><td>%.0f</td><td>%.0f</td><td>%.0f</td>' ...
                '<td>%.0f</td><td>%.4g</td><td>%.4g</td>' ...
                '<td>%.0f</td><td>%.4g</td><td>%.4g</td>' ...
                '<td>%.4g</td><td>[%.4g, %.4g]</td><td>%.3f</td></tr>\n'], ...
                descriptiveStats.Xmm(1), descriptiveStats.Ymm(1), ...
                descriptiveStats.TimeMs(1), descriptiveStats.N1(1), ...
                descriptiveStats.Mean1(1), descriptiveStats.SD1(1), ...
                descriptiveStats.N2(1), descriptiveStats.Mean2(1), ...
                descriptiveStats.SD2(1), descriptiveStats.MeanDifference(1), ...
                descriptiveStats.DifferenceCI95Lower(1), ...
                descriptiveStats.DifferenceCI95Upper(1), ...
                descriptiveStats.HedgesG(1));

            fprintf(fid, '</table>\n');
            fprintf(fid, ['<p class="note"><b>Note.</b> CI = confidence interval; ' ...
                'SD = standard deviation. These estimates are descriptive because ' ...
                'the sensor location and latency were selected from the same ' ...
                'group-contrast map. They must not be presented as an independent ' ...
                'ROI analysis or as additional confirmatory evidence.</p>\n']);
        end

        fprintf(fid, ['<p class="note"><b>Word use:</b> Open this HTML file ' ...
            'directly in Microsoft Word. The tables remain editable. Copy each ' ...
            'table into the appropriate thesis section, add your own table number, ' ...
            'and then save the document as DOCX.</p>\n']);
        fprintf(fid, '</body>\n</html>\n');

    catch cleanupError
        fclose(fid);
        rethrow(cleanupError);
    end
    fclose(fid);
end


function escaped = htmlEscape(value)
    escaped = char(string(value));
    escaped = strrep(escaped, '&', '&amp;');
    escaped = strrep(escaped, '<', '&lt;');
    escaped = strrep(escaped, '>', '&gt;');
    escaped = strrep(escaped, '"', '&quot;');
end


function textValue = pValueText(pValue)
    if ~isfinite(pValue)
        textValue = '&mdash;';
    elseif pValue < 0.001
        textValue = '&lt;.001';
    else
        textValue = sprintf('%.3f', pValue);
        if startsWith(textValue, '0')
            textValue = textValue(2:end);
        end
    end
end


function writeReadme(fileName)
    fid = fopen(fileName, 'w');
    if ~(fid ~= -1)
        error('Could not create reporting checklist.');
    end

    try


        fprintf(fid, ['SENSOR-SPACE REPORTING CHECKLIST\n\n' ...
            'PRIMARY INFERENCE\n' ...
            '1. Report both directional contrasts.\n' ...
            '2. Report voxel/peak-level p_FWE, T, Z, df, x, y, latency, and k.\n' ...
            '3. Report cluster-level p_FWE separately; do not call a cluster ' ...
            'significant unless that p-value is below .05.\n' ...
            '4. State voxel-level FWE p < .05 and k = 0.\n\n' ...
            'METHODS\n' ...
            '5. Report n=20 monolingual and n=23 bilingual.\n' ...
            '6. Report unequal variances and independence assumed.\n' ...
            '7. Report Scalp x Time conversion, 0-400 ms, 32x32x103, and ' ...
            'the [5 5 10] mm/mm/ms applied smoothing kernel.\n' ...
            '8. Distinguish the applied smoothing kernel from SPM-estimated ' ...
            'residual smoothness.\n\n' ...
            'INTERPRETATION\n' ...
            '9. x/y are sensor-image coordinates; time is milliseconds.\n' ...
            '10. Do not assign a cortical region without source reconstruction.\n' ...
            '11. Peak plots/effect sizes are descriptive because selection and ' ...
            'visualisation use the same data.\n']);

    catch cleanupError
        fclose(fid);
        rethrow(cleanupError);
    end
    fclose(fid);
end
