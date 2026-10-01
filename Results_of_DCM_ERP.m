function outputFolder = Results_of_DCM_ERP(cfg)
% Read-only extraction of saved ERP DCM / PEB / automatic-search BMA results.
% Run after adding SPM to the MATLAB path. Does NOT estimate any model.
% Requires MATLAB R2020b+ and SPM. Word/Report Generator are NOT required.
% Edit defaults below only if your paths or verified subject manifest differ.
% All tables are written to a genuine DOCX; figures: PNG 600 dpi, PDF, FIG.
% No source MAT/DAT file is overwritten. See the accompanying reporting guide.
    if nargin < 1
        cfg = struct;
    end
    cfg = defaults(cfg);
    if ~(exist('spm','file') == 2)
        error('Add your existing SPM installation to the MATLAB path first.');
    end

    if ~(exist('spm_vec','file') == 2)
        error('SPM utilities are not available.');
    end

    if ~isempty(intersect(cfg.MonoIDs,cfg.BiIDs))
        error('Group ID lists overlap.');
    end

    if ~(numel(unique([cfg.MonoIDs cfg.BiIDs])) == 43)
        error('The manifest must contain 43 unique subjects.');
    end

    pebResults = loadvar(cfg.PEBFile,'PEB');
    bmaResults = loadvar(cfg.BMAFile,'BMA');
    groupDCMs = loadvar(cfg.GCMFile,'GCM');
    if ~(iscell(groupDCMs) && isequal(size(groupDCMs),[43 1]))
        error('Expected a 43-by-1 GCM: subjects by models.');
    end

    if iscell(pebResults)
        if ~(numel(pebResults) == 1)
            error('Select one PEB model.');
        end
        pebResults = pebResults{1};
    end
    if ~(isstruct(pebResults) && isstruct(bmaResults))
        error('Expected scalar PEB and BMA structures.');
    end

    if ~(isfield(pebResults,'Pnames') && isfield(pebResults,'M') && isfield(pebResults.M,'X'))
        error('PEB names/design missing.');
    end

    parameterNames = strs(pebResults.Pnames);
    X = full(pebResults.M.X);
    numberOfParameters = numel(parameterNames);
    if ~(numberOfParameters == 14 && isequal(size(X),[43 2]))
        error('Expected 14 connections and an intercept + group design.');
    end

    if ~(all(isfinite(X(:))) && rank(X) == 2 && max(abs(X(:,1)-1))<1e-10)
        error('Invalid two-column design.');
    end

    if ~(isnumeric(bmaResults.Ep) && numel(bmaResults.Ep) == numberOfParameters*2)
        error('Unexpected BMA.Ep layout.');
    end

    if ~(isfield(bmaResults,'Pp') && isnumeric(bmaResults.Pp) && numel(bmaResults.Pp) == numberOfParameters*2)
        error('Automatic-search BMA.Pp required.');
    end

    % SPM may store posterior vectors as sparse. Keep report values dense from
    % here onward: sprintf/compose, plots and Word tables require full inputs.
    posteriorMeans = full(double(bmaResults.Ep(:)));
    retentionProbabilities = full(double(bmaResults.Pp(:)));
    posteriorCovariance = full(double(bmaResults.Cp));
    validate_cov(posteriorCovariance,numel(posteriorMeans),'BMA');
    if ~(all(isfinite(posteriorMeans)) && all(isfinite(retentionProbabilities)) && all(retentionProbabilities >= 0 & retentionProbabilities <= 1))
        error('Non-finite estimates or invalid Pp.');
    end

    if isfield(bmaResults,'Pnames')
        if ~isequal(strs(bmaResults.Pnames),parameterNames)
            error('PEB and BMA parameter names differ.');
        end
    end
    if isfield(bmaResults,'M') && isfield(bmaResults.M,'X')
        if ~(isequal(size(bmaResults.M.X),size(X)) && norm(full(bmaResults.M.X)-X,'fro')<1e-10)
            error('PEB and BMA designs differ.');
        end

    else
        error('BMA.M.X missing: cannot verify that the BMA belongs to this design.');
    end
    if isfield(pebResults.M,'W')
        if ~(isequal(size(pebResults.M.W),[numberOfParameters numberOfParameters]) && norm(full(pebResults.M.W)-eye(numberOfParameters),'fro')<1e-10)
            error('Non-identity within-subject design requires a different mapping.');
        end
    end
    familyNumber = zeros(numberOfParameters,1);
    targetIndex = familyNumber;
    sourceIndex = familyNumber;
    for parameterIndex = 1:numberOfParameters
        parameterParts = regexp(char(parameterNames(parameterIndex)),'^A\{([123])\}\((\d+),(\d+)\)$','tokens','once');
        if isempty(parameterParts)
            error('Unsupported parameter name: %s',parameterNames(parameterIndex));
        end

        familyNumber(parameterIndex) = str2double(parameterParts{1});
        targetIndex(parameterIndex) = str2double(parameterParts{2});
        sourceIndex(parameterIndex) = str2double(parameterParts{3});
    end
    expected = [1 3 1;1 4 2;1 5 3;1 6 4;2 1 3;2 2 4;2 3 5;2 4 6;3 2 1;3 1 2;3 4 3;3 3 4;3 6 5;3 5 6];
    if ~isequal(sortrows([familyNumber targetIndex sourceIndex]),sortrows(expected))
        error('The 14 connections do not match the stated research questions.');
    end


    % Resolve subject identity from the DATA file, never from template subject1.
    subjectIDs = zeros(43,1);
    subjectDCMs = cell(43,1);
    dcmNames = strings(43,1);
    datafiles = dcmNames;
    for subjectIndex = 1:43
        subjectDCM = groupDCMs{subjectIndex};
        if ischar(subjectDCM) || isstring(subjectDCM)
            subjectDCM = loadvar(char(subjectDCM),'DCM');
        end
        if ~(isstruct(subjectDCM) && isfield(subjectDCM,'xY') && isfield(subjectDCM.xY,'Dfile'))
            error('DCM %d has no xY.Dfile.',subjectIndex);
        end

        datafiles(subjectIndex) = string(subjectDCM.xY.Dfile);
        subjectIDs(subjectIndex) = data_id(datafiles(subjectIndex));
        if ~isfield(subjectDCM,'name')
            error('DCM name required to verify PEB row order.');
        end
        dcmNames(subjectIndex) = stem(subjectDCM.name);
        subjectDCMs{subjectIndex} = subjectDCM;
    end
    if ~(numel(unique(subjectIDs)) == 43 && isequal(sort(subjectIDs),sort([cfg.MonoIDs cfg.BiIDs]')))
        error('GCM subject IDs differ from the manifest.');
    end

    if ~isfield(pebResults,'Snames')
        error('PEB.Snames missing; subject-order provenance cannot be verified.');
    end

    pebSubjectNames = strs(pebResults.Snames);
    if ~(numel(pebSubjectNames) == 43)
        error('PEB subject count differs.');
    end

    for subjectIndex = 1:43
        pebSubjectNames(subjectIndex) = stem(pebSubjectNames(subjectIndex));
    end
    if ~(numel(unique(lower(dcmNames))) == 43 && isequal(lower(pebSubjectNames),lower(dcmNames)))
        error('GCM and PEB subject order/names differ. Do not reinterpret group effects until corrected.');
    end

    isMonolingual = false(43, 1);
    isBilingual = false(43, 1);
    for subjectIndex = 1:43
        if ismember(subjectIDs(subjectIndex), cfg.MonoIDs)
            isMonolingual(subjectIndex) = true;
        elseif ismember(subjectIDs(subjectIndex), cfg.BiIDs)
            isBilingual(subjectIndex) = true;
        end
    end
    monolingualCodeMean = mean(X(isMonolingual, 2));
    bilingualCodeMean = mean(X(isBilingual, 2));
    groupCodeDifference = monolingualCodeMean - bilingualCodeMean;
    if ~(max(abs(X(isMonolingual,2)-monolingualCodeMean))<1e-10 && max(abs(X(isBilingual,2)-bilingualCodeMean))<1e-10 && abs(groupCodeDifference)>1e-10)
        error('Second covariate does not agree with the group manifest.');
    end

    groupNames = repmat("Bilingual",43,1);
    groupNames(isMonolingual) = "Monolingual";
    sourceNames = strs(subjectDCMs{1}.Sname);
    if ~(numel(sourceNames) == 6)
        error('Expected six nodes.');
    end

    roles = ["L_EVC";"R_EVC";"L_LOC";"R_LOC";"L_IT";"R_IT"];
    aliases = {{'levc','lv1'},{'revc','rv1'},{'lloc'},{'rloc'},{'lit','litg'},{'rit','ritg'}};
    for itemIndex = 1:6
        clean = regexprep(lower(char(sourceNames(itemIndex))),'[^a-z0-9]','');
        if ~ismember(clean,aliases{itemIndex})
            error('Node %d is %s; verify the node order against EVC/LOC/IT before changing this check.',itemIndex,sourceNames(itemIndex));
        end

    end
    sourceCoordinates = full(double(subjectDCMs{1}.Lpos));
    if ~(isequal(size(sourceCoordinates),[3 6]) && all(isfinite(sourceCoordinates(:))))
        error('Expected 3-by-6 MNI prior positions.');
    end

    for subjectIndex = 1:43
        subjectDCM = subjectDCMs{subjectIndex};
        if ~isequal(strs(subjectDCM.Sname),sourceNames)
            error('Source order differs for subject %d.',subjectIDs(subjectIndex));
        end

        if ~(strcmpi(subjectDCM.options.analysis,'ERP') && strcmpi(subjectDCM.options.model,'ERP'))
            error('This report is for the ERP neuronal model with ERP analysis only.');
        end

        if ~(isequal(subjectDCM.A,subjectDCMs{1}.A) && isequal(subjectDCM.C,subjectDCMs{1}.C))
            error('Network or input mask differs across subjects.');
        end

        if ~isequal(subjectDCM.Lpos,subjectDCMs{1}.Lpos)
            error('Source priors differ; report them separately.');
        end

        if ~isequal(subjectDCM.options.Tdcm,subjectDCMs{1}.options.Tdcm)
            error('DCM time windows differ across subjects.');
        end

        if isfield(subjectDCM.xY,'code') && isfield(subjectDCMs{1}.xY,'code')
            if ~isequal(strs(subjectDCM.xY.code),strs(subjectDCMs{1}.xY.code))
                error('Condition labels differ across subjects.');
            end

        end
        for parameterIndex = 1:numberOfParameters
            if ~(subjectDCM.A{familyNumber(parameterIndex)}(targetIndex(parameterIndex),sourceIndex(parameterIndex)) ~= 0)
                error('Named connection absent from DCM.A.');
            end
        end
    end

    % All parameter positions are mapped by their saved names, not guessed order.
    interceptIndex = (1:numberOfParameters)';
    contrastIndex = numberOfParameters + interceptIndex;
    groupDifference = zeros(numberOfParameters, 1);
    posteriorSD = zeros(numberOfParameters, 1);
    intervalLower = zeros(numberOfParameters, 1);
    intervalUpper = zeros(numberOfParameters, 1);
    monoMean = zeros(numberOfParameters, 1);
    biMean = zeros(numberOfParameters, 1);
    monoSD = zeros(numberOfParameters, 1);
    biSD = zeros(numberOfParameters, 1);
    retainedProbability = zeros(numberOfParameters, 1);
    passesThreshold = false(numberOfParameters, 1);
    direction = strings(numberOfParameters, 1);

    for parameterIndex = 1:numberOfParameters
        meanIndex = interceptIndex(parameterIndex);
        groupIndex = contrastIndex(parameterIndex);

        % The group difference depends on the actual saved group codes.
        groupDifference(parameterIndex) = groupCodeDifference * posteriorMeans(groupIndex);
        groupVariance = posteriorCovariance(groupIndex, groupIndex);
        posteriorSD(parameterIndex) = abs(groupCodeDifference) * sqrt(max(0, groupVariance));
        intervalLower(parameterIndex) = groupDifference(parameterIndex) - 1.95996398454005 * posteriorSD(parameterIndex);
        intervalUpper(parameterIndex) = groupDifference(parameterIndex) + 1.95996398454005 * posteriorSD(parameterIndex);

        monoMean(parameterIndex) = posteriorMeans(meanIndex) + monolingualCodeMean * posteriorMeans(groupIndex);
        biMean(parameterIndex) = posteriorMeans(meanIndex) + bilingualCodeMean * posteriorMeans(groupIndex);

        % Keep intercept/slope covariance in the group uncertainty.
        interceptVariance = posteriorCovariance(meanIndex, meanIndex);
        interceptGroupCovariance = posteriorCovariance(meanIndex, groupIndex);
        monoVariance = interceptVariance + 2*monolingualCodeMean*interceptGroupCovariance + monolingualCodeMean^2*groupVariance;
        biVariance = interceptVariance + 2*bilingualCodeMean*interceptGroupCovariance + bilingualCodeMean^2*groupVariance;
        monoSD(parameterIndex) = sqrt(max(0, monoVariance));
        biSD(parameterIndex) = sqrt(max(0, biVariance));

        retainedProbability(parameterIndex) = retentionProbabilities(groupIndex);
        passesThreshold(parameterIndex) = retainedProbability(parameterIndex) > cfg.Threshold;
        direction(parameterIndex) = "No strong retained effect";
        if passesThreshold(parameterIndex)
            if groupDifference(parameterIndex) > 0
                direction(parameterIndex) = "Monolingual > Bilingual";
            elseif groupDifference(parameterIndex) < 0
                direction(parameterIndex) = "Bilingual > Monolingual";
            end
        end
    end
    if ~(max(abs((monoMean-biMean)-groupDifference))<1e-9)
        error('Modeled group estimates disagree with the PEB contrast.');
    end

    family = ["Forward";"Backward";"Lateral"];
    edge = sourceNames(sourceIndex)+" -> "+sourceNames(targetIndex);
    T = table(parameterNames,family(familyNumber),sourceNames(sourceIndex),sourceNames(targetIndex),monoMean,monoSD,biMean,biSD,groupDifference,posteriorSD,intervalLower,intervalUpper,retainedProbability,passesThreshold,direction, ...
        'VariableNames',{'Parameter','Family','Source','Target','MonoModelMean','MonoModelSD','BiModelMean','BiModelSD','MonoMinusBi','PosteriorSD','ApproxCrI_Lower','ApproxCrI_Upper','PpRetained','Strong','Direction'});
    % Arrange by question and hierarchy while retaining explicit parameter IDs.
    [~,ix] = ismember(expected,[familyNumber targetIndex sourceIndex],'rows');
    T = T(ix,:);
    familyNumber = familyNumber(ix);
    sourceIndex = sourceIndex(ix);
    targetIndex = targetIndex(ix);
    edge = edge(ix);
    parameterNames = parameterNames(ix);
    groupDifference = groupDifference(ix);
    posteriorSD = posteriorSD(ix);
    intervalLower = intervalLower(ix);
    intervalUpper = intervalUpper(ix);
    retainedProbability = retainedProbability(ix);
    passesThreshold = passesThreshold(ix);
    meanSD = sqrt(max(0,diag(posteriorCovariance(1:numberOfParameters,1:numberOfParameters))));
    TM = table(strs(pebResults.Pnames),posteriorMeans(1:numberOfParameters),meanSD,retentionProbabilities(1:numberOfParameters),'VariableNames',{'Parameter','Intercept','PosteriorSD','PpRetained'});
    TM = TM(ix,:);
    NodeTable = table((1:6)',sourceNames,roles,sourceCoordinates(1,:)',sourceCoordinates(2,:)',sourceCoordinates(3,:)', ...
        'VariableNames',{'Index','SavedName','IntendedRole','MNI_X','MNI_Y','MNI_Z'});

    % Check stored first-level fit predictions in their fitted spatial-mode space.
    freeEnergy = nan(43,1);
    fitR2 = freeEnergy;
    numberOfModes = freeEnergy;
    fitOK = false(43,1);
    notes = strings(43,1);
    fits = cell(43,1);
    for subjectIndex = 1:43
        subjectDCM = subjectDCMs{subjectIndex};
        try
            if ~(isfield(subjectDCM,'Ep') && all(isfinite(spm_vec(subjectDCM.Ep))))
                error('Invalid first-level posterior.');
            end

            validate_cov(full(subjectDCM.Cp),numel(spm_vec(subjectDCM.Ep)),'DCM');
            if ~(isfield(subjectDCM,'F') && isscalar(subjectDCM.F) && isfinite(subjectDCM.F))
                error('Invalid first-level F.');
            end
            freeEnergy(subjectIndex) = subjectDCM.F;
            storedFit = getfit(subjectDCM);
            fitR2(subjectIndex) = storedFit.R2;
            numberOfModes(subjectIndex) = size(storedFit.Y,2);
            fits{subjectIndex} = storedFit;
            fitOK(subjectIndex) = true;
            notes(subjectIndex) = "Stored predictions checked; not a convergence certificate";
        catch err
            notes(subjectIndex) = string(err.message);
        end
    end
    QC = table((1:43)',subjectIDs,groupNames,X(:,1),X(:,2),freeEnergy,fitR2,numberOfModes,fitOK,notes,datafiles, ...
        'VariableNames',{'PEBRow','SubjectID','Group','InterceptX','GroupX','FreeEnergy','FitR2Percent','Modes','FitArraysOK','Note','DataFile'});
    rqCount = zeros(3,1);
    totals = [4;4;6];
    for itemIndex = 1:3
        for parameterIndex = 1:numberOfParameters
            if familyNumber(parameterIndex) == itemIndex && passesThreshold(parameterIndex)
                rqCount(itemIndex) = rqCount(itemIndex) + 1;
            end
        end
    end
    RQ = table((1:3)',family,totals,rqCount,'VariableNames',{'Question','ConnectionFamily','TestedConnections','StrongRetainedEffects'});
    gamma = "NOT STORED: verify saved batch";
    if isfield(bmaResults,'gamma')
        gamma = string(mat2str(full(bmaResults.gamma),12));
    end
    settings = collect_settings(subjectDCMs);

    stamp = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
    outputFolder = fullfile(cfg.OutputRoot,['DCM_ERP_Report_' stamp]);
    if exist(outputFolder,'dir')
        error('Output exists.');
    end

    mkdir(outputFolder);
    figdir = fullfile(outputFolder,'figures');
    mkdir(figdir);
    fitdir = fullfile(figdir,'individual_fits');
    mkdir(fitdir);
    logfile = fullfile(outputFolder,'REPORT_NOTES.txt');
    lines = ["Revised average-reference QC: PASS 43/43 as reported by the user; actual MAT files were not independently inspected here."; ...
        "This script does not estimate, re-reference, resave or overwrite input analyses."; ...
        "Subject groups come from the explicit manifest in the script; verify them against recruitment records."; ...
        "Subject order verified by PEB.Snames and GCM names; identity resolved from xY.Dfile."; ...
        "PpRetained is SPM automatic-search model retention probability; it is NOT a p-value or P(beta>0)."; ...
        "For positive null prior variance, the comparison is against strong shrinkage, not exact absence."; ...
        "Saved null prior setting (gamma): " + gamma; ...
        "Intervals: BMA mean +/- 1.96 posterior SD, Gaussian moment approximation, not exact mixture quantiles."; ...
        "MonoModelMean and BiModelMean are PEB-predicted values at each group's saved covariate code, not separate group-specific model fits."; ...
        "ERP A parameters: dimensionless log scaling. Negative group difference does not mean inhibition."; ...
        "No effect passing the threshold is not evidence of equivalence."; ...
        "The three question summaries count supported edges; they are NOT joint/omnibus Bayes factors."; ...
        "Automatic greedy-search Pp is conditional on the searched model space; 0/1 need not mean certainty."; ...
        "No model posterior bar plot is fabricated: BMA alone does not store the full BMR model search history."; ...
        "Stored fit R2=100*(1-SSE/SST), SST centered within each mode/trial; can be negative."; ...
        "H+R is the observed projected response in the stored DCM; arbitrary scaled units, not microvolts."; ...
        "Free energies are recorded for provenance, not ranked between different participants."; ...
        "Sensor eigenmodes are subject-specific: no cross-subject averaging of mode waveforms."; ...
        "Confirm that DCM input file paths correspond to the datasets covered by the final PASS 43/43 reference QC."; ...
        "No original source-level activation maps or new cognitive/causal group claims are generated."; ...
        "Group contrast multiplier (x_mono - x_bi): " + string(groupCodeDifference); ...
        "Mean of group covariate: " + string(mean(X(:,2))); ...
        "Counts Mono/Bi: " + string(sum(isMonolingual)) + "/" + string(sum(isBilingual)); ...
        "Fit arrays checked: " + string(sum(fitOK)) + "/43"; ...
        "MATLAB: " + string(version); "SPM path: " + string(which('spm')); ...
        "GCM: " + string(cfg.GCMFile); "PEB: " + string(cfg.PEBFile); "BMA: " + string(cfg.BMAFile)];
    writeutf8(logfile,strjoin(lines,newline));
    save(fullfile(outputFolder,'Extracted_Report_Values.mat'),'T','TM','NodeTable','QC','RQ','settings','cfg','X','gamma','ix');
    write_docx(fullfile(outputFolder,'DCM_ERP_Results_Tables.docx'),T,TM,NodeTable,QC,RQ,settings,lines,cfg);

    forest_plot(edge,groupDifference,intervalLower,intervalUpper,retainedProbability,familyNumber,cfg.Threshold,fullfile(figdir,'01_Group_difference_all14'));
    network_plot(sourceNames,sourceIndex,targetIndex,familyNumber,groupDifference,passesThreshold,fullfile(figdir,'02_Directed_group_effects'));
    design_plot(X,subjectIDs,groupNames,fullfile(figdir,'03_Subject_order_and_design'));
    qc_plot(subjectIDs,groupNames,fitR2,fullfile(figdir,'04_Stored_fit_quality'));
    % Export every available fit. Display examples are chosen objectively, near
    % the median R2 within each group, not from the best-fitting participants.
    for subjectIndex = find(fitOK)'
        if cfg.AllIndividualFitFigures
            fprintf('Exporting stored fit: subject %d (%d/43)\n',subjectIDs(subjectIndex),subjectIndex);
            fit_plot(fits{subjectIndex},subjectIDs(subjectIndex),groupNames(subjectIndex),fullfile(fitdir,sprintf('Subject_%02d',subjectIDs(subjectIndex))));
        end
    end
    for currentGroup = ["Monolingual","Bilingual"]
        groupSubjectRows = find(fitOK & groupNames == currentGroup);
        if isempty(groupSubjectRows)
            continue;
        end
        [~,itemIndex] = min(abs(fitR2(groupSubjectRows)-median(fitR2(groupSubjectRows))));
        subjectIndex = groupSubjectRows(itemIndex);
        fit_plot(fits{subjectIndex},subjectIDs(subjectIndex),groupNames(subjectIndex),fullfile(figdir,"05_Median_fit_"+currentGroup));
    end
    try
        anatomical_plot(sourceNames,sourceCoordinates,fullfile(figdir,'06_MNI_prior_nodes'));
    catch err
        writeutf8(fullfile(outputFolder,'ANATOMY_NOT_GENERATED.txt'),string(err.message));
        warning('Anatomical illustration skipped: %s',err.message);
    end
    % Save a local provenance copy of SPM functions, without altering SPM.
    prov = fullfile(outputFolder,'SPM_source_provenance');
    mkdir(prov);
    for spmFunctionName = ["spm_dcm_erp","spm_fx_erp","spm_dcm_peb","spm_dcm_peb_bmc","spm_dcm_bmr_all"]
        spmFunctionPath = which(char(spmFunctionName));
        if ~isempty(spmFunctionPath)
            copyfile(spmFunctionPath,fullfile(prov,char(spmFunctionName+".m")));
        end
    end
    writeutf8(fullfile(outputFolder,'REPORT_COMPLETE.txt'),"Results extraction, DOCX tables and figure exports completed. Check individual fit flags in Extracted_Report_Values.mat before interpretation.");
    fprintf('\nReport created (revised reference QC reported PASS 43/43):\n%s\n',outputFolder);
    fprintf('DOCX: %s\n',fullfile(outputFolder,'DCM_ERP_Results_Tables.docx'));
    disp(RQ);
end

function cfg = defaults(cfg)
    dataRoot = 'E:\Subjects44\SPM_MAT_DAT';
    dcmFolder = fullfile(dataRoot, 'GCM_DCM');
    defaultSettings = struct;
    defaultSettings.GCMFile = fullfile(dcmFolder, 'GCM_GCM_ERP_43_estimated.mat');
    defaultSettings.PEBFile = fullfile(dcmFolder, 'PEB_ERP_A_Mono_vs_Bi.mat');
    defaultSettings.BMAFile = fullfile(dcmFolder, 'BMA_search_PEB_ERP_A_Mono_vs_Bi.mat');
    defaultSettings.OutputRoot = dcmFolder;
    defaultSettings.Threshold = 0.95;
    defaultSettings.AllIndividualFitFigures = true;
    defaultSettings.MonoIDs = [2 3 4 5 9 11 12 13 16 19 21 22 25 30 31 32 34 35 38 47];
    defaultSettings.BiIDs = [1 7 8 10 14 20 24 26 27 28 29 33 36 37 39 40 41 42 43 44 45 46 48];

    settingNames = fieldnames(defaultSettings);
    for settingIndex = 1:numel(settingNames)
        fieldName = settingNames{settingIndex};
        if ~isfield(cfg, fieldName)
            cfg.(fieldName) = defaultSettings.(fieldName);
        end
    end
    if ~(cfg.Threshold>0.5 && cfg.Threshold<1)
        error('Use a pre-specified posterior threshold between .5 and 1.');
    end

end

function variableValue = loadvar(filePath,variableName)
    if ~isfile(filePath)
        error('File not found: %s',filePath);
    end
    loadedFile = load(filePath,variableName);
    if ~isfield(loadedFile,variableName)
        error('Variable %s not found in %s',variableName,filePath);
    end
    variableValue = loadedFile.(variableName);
end
function textValues = strs(textValues)
    if ischar(textValues)
        textValues = string(cellstr(textValues));
    else
        textValues = string(textValues);
    end
    textValues = strtrim(textValues(:));
end
function fileStem = stem(inputPath)
    inputPath = replace(string(inputPath),'\','/');
    [~,fileStem] = fileparts(char(inputPath));
    fileStem = string(fileStem);
end
function id = data_id(dataPath)
% Match the final dataset name, not the enclosing DCM template name.
    normalisedPath = replace(string(dataPath),'\','/');
    [folder,name] = fileparts(char(normalisedPath));
    % Both CaMspmeeg_sub13_* and CaMspmeeg_sub-13_* occur in this dataset.
    nameParts = regexp(name,'(?i)^CaMspmeeg_sub[-_]?(\d+)(?:_|$)','tokens','once');
    if isempty(nameParts)
        error('Unrecognized data filename: %s. Expected CaMspmeeg_sub13_* or CaMspmeeg_sub-13_*.',dataPath);
    end

    id = str2double(nameParts{1});
    [~,subjectFolder] = fileparts(folder);
    if ~isempty(regexp(subjectFolder,'^\d+$','once'))
        if ~(str2double(subjectFolder) == id)
            error('Subject folder %s conflicts with subject %d in data filename: %s',subjectFolder,id,dataPath);
        end

    end
end
function validate_cov(covarianceMatrix,numberOfParameters,label)
    if ~(isnumeric(covarianceMatrix) && isreal(covarianceMatrix) && isequal(size(covarianceMatrix),[numberOfParameters numberOfParameters]) && all(isfinite(covarianceMatrix(:))))
        error('Invalid %s covariance size/values.',label);
    end

    scale = max(1,norm(covarianceMatrix,'fro'));
    if ~(norm(covarianceMatrix-covarianceMatrix','fro')<1e-8*scale)
        error('Asymmetric %s covariance.',label);
    end

    % Full eig is appropriate for the 28-by-28 BMA; use diagonal and Cholesky
    % with a small numerical tolerance for the larger first-level matrices.
    if ~(min(diag(covarianceMatrix)) >= -1e-9*scale)
        error('Negative %s posterior variance.',label);
    end

    [~,flag] = chol((covarianceMatrix+covarianceMatrix')/2 + 1e-9*scale*eye(numberOfParameters));
    if ~(flag == 0)
        error('Non-positive-semidefinite %s covariance.',label);
    end

end
function fitInformation = getfit(subjectDCM)
    if ~(iscell(subjectDCM.H) && iscell(subjectDCM.R) && numel(subjectDCM.H) == numel(subjectDCM.R))
        error('Expected saved H/R cell arrays.');
    end

    if ~(numel(subjectDCM.H) == 1)
        error('This report expects one all_images evoked condition.');
    end

    predictedResponse = full(double(subjectDCM.H{1}));
    residualResponse = full(double(subjectDCM.R{1}));
    timeMs = full(double(subjectDCM.xY.pst(:)));
    if ~(isequal(size(predictedResponse),size(residualResponse)) && size(predictedResponse,1) == numel(timeMs) && all(isfinite(predictedResponse(:))) && all(isfinite(residualResponse(:))))
        error('Invalid prediction/residual arrays.');
    end

    observedResponse = predictedResponse + residualResponse;
    sumSquaredErrors = 0;
    totalSumSquares = 0;
    for modeIndex = 1:size(observedResponse, 2)
        modeMean = mean(observedResponse(:, modeIndex));
        for timeIndex = 1:size(observedResponse, 1)
            sumSquaredErrors = sumSquaredErrors + residualResponse(timeIndex, modeIndex)^2;
            deviation = observedResponse(timeIndex, modeIndex) - modeMean;
            totalSumSquares = totalSumSquares + deviation^2;
        end
    end
    if ~(totalSumSquares>0)
        error('Observed fitted response has no variance.');
    end

    if isfield(subjectDCM,'M') && isfield(subjectDCM.M,'R') && isfield(subjectDCM.M,'U') && isfield(subjectDCM.xY,'y')
        projectedResponse = full(double(subjectDCM.M.R*subjectDCM.xY.observedResponse{1}*subjectDCM.M.U));
        if ~(isequal(size(projectedResponse),size(observedResponse)) && norm(projectedResponse-observedResponse,'fro') <= 1e-6*max(1,norm(observedResponse,'fro')))
            error('H+R does not match M.R*xY.y*M.U.');
        end

    end
    fitInformation = struct;
    fitInformation.H = predictedResponse;
    fitInformation.Y = observedResponse;
    fitInformation.R = residualResponse;
    fitInformation.t = timeMs;
    fitInformation.R2 = 100*(1-sumSquaredErrors/totalSumSquares);
end
function T = collect_settings(subjectDCMs)
    keys = {'analysis','model','spatial','Tdcm','trials','Nmodes','D','h','onset','dur','symmetry','location','lock','multiC'};
    rows = cell(0,3);
    for settingIndex = 1:numel(keys)
        savedValues = strings(numel(subjectDCMs),1);
        for subjectIndex = 1:numel(subjectDCMs)
            if isfield(subjectDCMs{subjectIndex}.options,keys{settingIndex})
                savedValues(subjectIndex) = valstr(subjectDCMs{subjectIndex}.options.(keys{settingIndex}));
            else
                savedValues(subjectIndex) = "Not stored";
            end
        end
        distinctValues = unique(savedValues,'stable');
        rows(end+1,:) = {keys{settingIndex},char(strjoin(distinctValues,' | ')),num2str(numel(distinctValues))}; %#ok<AGROW>
    end
    if isfield(subjectDCMs{1}.xY,'code')
        rows(end+1,:) = {'Condition labels',char(strjoin(strs(subjectDCMs{1}.xY.code),', ')),'1'};
    end
    rows(end+1,:) = {'Driving input mask C',char(valstr(subjectDCMs{1}.C)),'1'};
    T = cell2table(rows,'VariableNames',{'Option','SavedValues','NumberOfDistinctValues'});
end
function formattedValue = valstr(inputValue)
    if isnumeric(inputValue) || islogical(inputValue)
        formattedValue = string(mat2str(full(inputValue),8));
    else
        formattedValue = string(inputValue);
    end
    if numel(formattedValue)>1
        formattedValue = strjoin(formattedValue(:)',', ');
    end
end

function figureHandle = whitefig(figureWidth,figureHeight)
    figureHandle = figure('Visible','off','Color','w','Position',[50 50 figureWidth figureHeight]);
    set(figureHandle,'DefaultAxesFontName','Arial','DefaultTextFontName','Arial','DefaultAxesFontSize',11,'DefaultTextInterpreter','none');
end
function exportfig(figureHandle,outputBase)
    savefig(figureHandle,char(outputBase+".fig"));
    exportgraphics(figureHandle,char(outputBase+".png"),'Resolution',600,'BackgroundColor',figureHandle.Color);
    exportgraphics(figureHandle,char(outputBase+".pdf"),'ContentType','image','Resolution',300,'BackgroundColor',figureHandle.Color);
    close(figureHandle);
end
function forest_plot(edgeLabels,groupDifference,intervalLower,intervalUpper,retainedProbability,familyNumber,threshold,outputBase)
    figureHandle = whitefig(1300,880);
    ax = axes(figureHandle,'Position',[.25 .14 .54 .76]);
    hold(ax,'on');
    colors = [.85 .33 .10;0 .45 .70];
    for edgeIndex = 1:numel(groupDifference)
        edgeColour = [.58 .58 .58];
        if retainedProbability(edgeIndex)>threshold
            edgeColour = colors(1+(groupDifference(edgeIndex)<0),:);
        end
        plot(ax,[intervalLower(edgeIndex) intervalUpper(edgeIndex)],[edgeIndex edgeIndex],'-','Color',edgeColour,'LineWidth',1.8);
        plot(ax,groupDifference(edgeIndex),edgeIndex,'o','Color',edgeColour,'MarkerFaceColor',edgeColour,'MarkerSize',6);
    end
    xline(ax,0,':','Color',[.25 .25 .25]);
    set(ax,'YDir','reverse','YLim',[.3 14.7],'YTick',1:14,'YTickLabel',edgeLabels,'TickLabelInterpreter','none');
    yline(ax,4.5,'-','Color',[.85 .85 .85]);
    yline(ax,8.5,'-','Color',[.85 .85 .85]);
    xlabel(ax,'Monolingual minus bilingual (dimensionless log scaling)');
    grid(ax,'on');
    ax.YGrid = 'off';
    box(ax,'off');
    ax2 = axes(figureHandle,'Position',[.82 .14 .17 .76],'YDir','reverse','YLim',[.3 14.7],'XLim',[0 1],'Visible','off');
    hold(ax2,'on');
    shortfamily = ["F","B","L"];
    for edgeIndex = 1:14
        text(ax2,0,edgeIndex,sprintf('%s   %s',char(shortfamily(familyNumber(edgeIndex))),char(probstr(retainedProbability(edgeIndex)))),'FontSize',11);
    end
    annotation(figureHandle,'textbox',[.815 .91 .17 .035],'String','Family   Pp retained','EdgeColor','none','FontSize',11);
    annotation(figureHandle,'textbox',[.05 .95 .9 .04],'String','All 14 group effects after PEB model averaging','EdgeColor','none','FontSize',18,'HorizontalAlignment','center');
    annotation(figureHandle,'textbox',[.08 .01 .85 .08],'String',sprintf('Orange: mono > bi; blue: bi > mono; grey: Pp <= %.2f.\nIntervals: mean +/- 1.96 posterior SD (Gaussian approximation). Pp is model retention, not sign probability.',threshold),'EdgeColor','none','FontSize',11,'HorizontalAlignment','center');
    exportfig(figureHandle,string(outputBase));
end
function network_plot(sourceNames,sourceIndex,targetIndex,familyNumber,groupDifference,passesThreshold,outputBase)
    backgroundColour = [.025 .035 .055];
    textColour = [.9 .94 .98];
    figureHandle = whitefig(1500,800);
    figureHandle.Color = backgroundColour;
    xy = [-.85 -1;.85 -1;-.85 0;.85 0;-.85 1;.85 1];
    labels = ["Forward","Backward","Lateral"];
    for familyIndex = 1:3
        ax = axes(figureHandle,'Position',[.025+(familyIndex-1)*.325 .19 .30 .64],'Color',backgroundColour);
        hold(ax,'on');
        for edgeIndex = find(familyNumber == familyIndex)'
            edgeColour = [.3 .33 .38];
            lineWidth = 1;
            if passesThreshold(edgeIndex)
                lineWidth = 2.8;
                if groupDifference(edgeIndex)>0
                    edgeColour = [1 .55 .18];
                else
                    edgeColour = [.2 .7 1];
                end
            end
            startPoint = xy(sourceIndex(edgeIndex),:);
            endPoint = xy(targetIndex(edgeIndex),:);
            edgeVector = endPoint-startPoint;
            unit = edgeVector/norm(edgeVector);
            startPoint = startPoint+.14*unit;
            endPoint = endPoint-.14*unit;
            curveOffset = [0 0];
            if familyIndex == 3
                curveOffset = .24*[-unit(2) unit(1)];
            end
            curveTimes = linspace(0,1,100)';
            control = (startPoint+endPoint)/2+curveOffset;
            curve = (1-curveTimes).^2.*startPoint+2*(1-curveTimes).*curveTimes.*control+curveTimes.^2.*endPoint;
            plot(ax,curve(:,1),curve(:,2),'Color',edgeColour,'LineWidth',lineWidth);
            arrowStart = curve(89,:);
            arrowVector = curve(96,:)-arrowStart;
            quiver(ax,arrowStart(1),arrowStart(2),arrowVector(1),arrowVector(2),0,'Color',edgeColour,'LineWidth',lineWidth,'MaxHeadSize',2.8);
        end
        for edgeIndex = 1:6
            plot(ax,xy(edgeIndex,1),xy(edgeIndex,2),'o','MarkerSize',13,'MarkerFaceColor',[.65 .7 .78],'MarkerEdgeColor',textColour);
            labelOffset = .20*sign(xy(edgeIndex,1));
            labelAlignment = 'left';
            if labelOffset<0
                labelAlignment = 'right';
            end
            text(ax,xy(edgeIndex,1)+labelOffset,xy(edgeIndex,2),sourceNames(edgeIndex),'Color',textColour,'HorizontalAlignment',labelAlignment,'FontSize',12,'Interpreter','none');
        end
        xlim(ax,[-1.95 1.95]);
        ylim(ax,[-1.35 1.35]);
        axis(ax,'off');
        title(ax,labels(familyIndex),'Color',textColour,'FontSize',17);
    end
    annotation(figureHandle,'textbox',[.04 .9 .92 .065],'String','Directed group differences in the specified visual network','Color',textColour,'EdgeColor','none','FontSize',20,'HorizontalAlignment','center');
    annotation(figureHandle,'textbox',[.06 .055 .88 .10],'String',{'Orange: monolingual > bilingual     Blue: bilingual > monolingual', ...
        'Grey: insufficient retention evidence at the chosen threshold; not an absent connection.', ...
        'Schematic hierarchy, not an anatomical map. Lines have fixed width within evidence classes.'},'Color',textColour,'EdgeColor','none','FontSize',12,'HorizontalAlignment','center');
    exportfig(figureHandle,string(outputBase));
end
function design_plot(X,subjectIDs,groupNames,outputBase)
    figureHandle = whitefig(1000,800);
    ax = axes(figureHandle,'Position',[.1 .1 .48 .79]);
    imagesc(ax,X);
    colormap(ax,gray);
    colorbar(ax);
    xticks(ax,[1 2]);
    xticklabels(ax,{'Intercept','Group covariate'});
    ylabel(ax,'PEB row order');
    title(ax,'Saved PEB design matrix');
    annotation(figureHandle,'textbox',[.64 .18 .3 .64],'String',sprintf('N = %d\nMonolingual = %d\nBilingual = %d\n\nRows use the stored GCM order.\nSubject IDs are not sorted here.\n\nSee the Word audit table for\nID-to-row and group mappings.\n\nFirst row ID: %d\nLast row ID: %d',numel(subjectIDs),sum(groupNames == "Monolingual"),sum(groupNames == "Bilingual"),subjectIDs(1),subjectIDs(end)),'EdgeColor','none','FontSize',13);
    exportfig(figureHandle,string(outputBase));
end
function qc_plot(subjectIDs,groupNames,fitR2,outputBase)
    figureHandle = whitefig(1200,650);
    ax = axes(figureHandle,'Position',[.08 .18 .88 .71]);
    hold(ax,'on');
    groupColours = [.85 .33 .10;0 .45 .70];
    groupLabels = ["Monolingual","Bilingual"];
    for groupIndex = 1:2
        subjectRows = find(groupNames == groupLabels(groupIndex));
        scatter(ax,subjectRows,fitR2(subjectRows),42,groupColours(groupIndex,:),'filled','DisplayName',groupLabels(groupIndex));
    end
    xticks(ax,1:43);
    xticklabels(ax,string(subjectIDs));
    xtickangle(ax,90);
    xlim(ax,[0 44]);
    xlabel(ax,'Subject ID in stored GCM order');
    ylabel(ax,'Stored fitted-space R2 (%)');
    grid(ax,'on');
    legend(ax,'Location','northoutside','Orientation','horizontal');
    annotation(figureHandle,'textbox',[.08 .01 .86 .06],'String','Descriptive fit diagnostic, not an automatic exclusion rule or proof of model convergence.','EdgeColor','none','HorizontalAlignment','center');
    exportfig(figureHandle,string(outputBase));
end
function fit_plot(fitInformation,id,groupName,outputBase)
    numberOfModes = size(fitInformation.Y,2);
    figureHandle = whitefig(1300,max(500,210*ceil(numberOfModes/3)));
    figureLayout = tiledlayout(figureHandle,ceil(numberOfModes/3),3,'TileSpacing','compact','Padding','compact');
    for modeIndex = 1:numberOfModes
        ax = nexttile(figureLayout);
        plot(ax,fitInformation.t,fitInformation.Y(:,modeIndex),'k-','LineWidth',1.2);
        hold(ax,'on');
        plot(ax,fitInformation.t,fitInformation.H(:,modeIndex),'--','Color',[.85 .33 .10],'LineWidth',1.2);
        title(ax,sprintf('Mode %d',modeIndex));
        xlabel(ax,'Time (ms)');
        ylabel(ax,'Scaled mode amplitude');
        box(ax,'off');
        if modeIndex == 1
            legend(ax,{'Observed H+R','Predicted H'},'Location','best');
        end
    end
    title(figureLayout,sprintf('Subject %d | %s | stored fit R2 %.1f%%',id,char(groupName),full(fitInformation.R2)),'FontSize',16,'Interpreter','none');
    exportfig(figureHandle,string(outputBase));
end
function anatomical_plot(sourceNames,sourceCoordinates,outputBase)
    mesh = fullfile(spm('Dir'),'canonical','cortex_8196.surf.gii');
    if ~isfile(mesh)
        error('SPM canonical cortical mesh not found; no substitute anatomy was invented.');
    end

    brainMesh = gifti(mesh);
    vertices = double(brainMesh.vertices);
    faces = double(brainMesh.faces);
    backgroundColour = [.025 .035 .055];
    textColour = [.9 .94 .98];
    figureHandle = whitefig(1500,800);
    figureHandle.Color = backgroundColour;
    % Views display all prior coordinates. This is explicitly not reconstructed activity.
    views = [-90 0;90 0;0 90];
    viewTitles = ["Left view","Right view","Superior view"];
    for viewIndex = 1:3
        ax = axes(figureHandle,'Position',[.02+(viewIndex-1)*.327 .25 .31 .58]);
        hold(ax,'on');
        patch(ax,'Faces',faces,'Vertices',vertices,'FaceColor',[.58 .62 .68],'FaceAlpha',.22,'EdgeColor','none');
        visibleNodes = 1:6;
        if viewIndex == 1
            visibleNodes = [1 3 5];
        elseif viewIndex == 2
            visibleNodes = [2 4 6];
        end
        scatter3(ax,sourceCoordinates(1,visibleNodes),sourceCoordinates(2,visibleNodes),sourceCoordinates(3,visibleNodes),60,[1 .62 .18],'filled');
        for nodeIndex = visibleNodes
            text(ax,sourceCoordinates(1,nodeIndex)+2,sourceCoordinates(2,nodeIndex)+2,sourceCoordinates(3,nodeIndex)+2,string(nodeIndex),'Color',textColour,'FontSize',13);
        end
        axis(ax,'equal');
        axis(ax,'off');
        view(ax,views(viewIndex,:));
        title(ax,viewTitles(viewIndex),'Color',textColour,'FontSize',17);
    end
    annotation(figureHandle,'textbox',[.04 .91 .92 .05],'String','Source-location priors on the SPM canonical cortex','Color',textColour,'EdgeColor','none','FontSize',19,'HorizontalAlignment','center');
    nodeLabels = strings(1,6);
    for nodeIndex = 1:6
        nodeLabels(nodeIndex) = string(nodeIndex)+" = "+sourceNames(nodeIndex);
    end
    annotation(figureHandle,'textbox',[.04 .12 .92 .075],'String',strjoin(nodeLabels,'     '),'Color',textColour,'EdgeColor','none','FontSize',12,'HorizontalAlignment','center','Interpreter','none');
    annotation(figureHandle,'textbox',[.05 .035 .9 .065],'String',{'MNI prior coordinates, not an activation map or optimized individual locations.', ...
        'Side views show ipsilateral nodes; superior view shows all six. Numbers refer to the node table.'},'Color',textColour,'EdgeColor','none','FontSize',12,'HorizontalAlignment','center');
    exportfig(figureHandle,string(outputBase));
end
function probabilityText = probstr(probability)
    if probability >= .99995
        probabilityText = ">=0.99995";
    elseif probability<.00005
        probabilityText = "<0.00005";
    else
        probabilityText = string(sprintf('%.4f',probability));
    end
end

function write_docx(path,T,TM,nodeTable,subjectQCTable,questionTable,settingsTable,notes,cfg)
% Minimal Office Open XML. Separate files in a freshly-created temp folder.
    temporaryFolder = tempname;
    mkdir(temporaryFolder);
    mkdir(fullfile(temporaryFolder,'_rels'));
    mkdir(fullfile(temporaryFolder,'word'));
    try

        body = para('DCM ERP Results and Audit',true)+para('Revised reference QC: PASS 43/43 as reported by the user. Confirm model input file provenance and group identity before publication.',false);
        body = body+para('All values below are extracted from saved models. No inversion or preprocessing was performed.',false);
        body = body+para('Participants and design',true)+para(sprintf('Monolingual n=%d; bilingual n=%d. Reported contrast is monolingual minus bilingual, accounting for the actual coding scale.',sum(subjectQCTable.Group == "Monolingual"),sum(subjectQCTable.Group == "Bilingual")),false);
        fitrows = strings(2,5);
        groupnames = ["Monolingual","Bilingual"];
        for groupIndex = 1:2
            groupFits = subjectQCTable.FitR2Percent(subjectQCTable.Group == groupnames(groupIndex)&subjectQCTable.FitArraysOK);
            fitrows(groupIndex,1:2) = [groupnames(groupIndex),string(numel(groupFits))];
            if isempty(groupFits)
                fitrows(groupIndex,3:5) = "Not available";
            else
                fitrows(groupIndex,3:5) = compose('%.2f',full([median(groupFits),min(groupFits),max(groupFits)]));
            end
        end
        body = body+xmltable(["Group","Checked fits","Median fit R2 %","Minimum","Maximum"],fitrows);
        body = body+para('Research question coverage',true)+xmltable(["Question","Family","Tested edges","Retained Pp > threshold"],cellstrings(table2cell(questionTable)));
        body = body+para(sprintf('Threshold: Pp > %.2f. These counts are edge-wise summaries, not joint Bayes factors.',cfg.Threshold),false);
        body = body+pagebreak()+para('All group differences',true);
        cells = strings(height(T),8);
        for rowIndex = 1:height(T)
            cells(rowIndex,:) = [T.Parameter(rowIndex),T.Family(rowIndex),T.Source(rowIndex)+" -> "+T.Target(rowIndex), ...
                string(sprintf('%.5f',full(T.MonoMinusBi(rowIndex)))),string(sprintf('%.5f',full(T.PosteriorSD(rowIndex)))), ...
                string(sprintf('[%.5f, %.5f]',full(T.ApproxCrI_Lower(rowIndex)),full(T.ApproxCrI_Upper(rowIndex)))),probstr(full(T.PpRetained(rowIndex))),string(full(T.Strong(rowIndex)))];
        end
        body = body+xmltable(["Parameter","Family","Source -> target","Mono - Bi","Post SD","Approx 95% interval","Pp retained","Pp > threshold"],cells);
        body = body+para('Units are dimensionless log scaling of ERP extrinsic coupling. Negative differences do not mean inhibitory connections. Intervals use a Gaussian moment approximation to BMA.',false);
        body = body+para('Positive null prior variance tests retention versus strong shrinkage, not a point-null at zero. Pp is neither a frequentist p-value nor the posterior sign probability.',false);
        body = body+para('Modeled values by group',true);
        cells = [T.Parameter, T.Source+" -> "+T.Target, compose('%.5f',full(T.MonoModelMean)), ...
            compose('%.5f',full(T.MonoModelSD)),compose('%.5f',full(T.BiModelMean)),compose('%.5f',full(T.BiModelSD))];
        body = body+xmltable(["Parameter","Source -> target","Mono modeled mean","Mono post SD","Bi modeled mean","Bi post SD"],cells);
        body = body+para('These are PEB/BMA modeled values evaluated at each group covariate code, not two independently estimated DCMs. Uncertainty includes intercept-slope covariance.',false);
        body = body+pagebreak()+para('Shared intercept parameters',true);
        ps = strings(height(TM),1);
        for rowIndex = 1:height(TM)
            ps(rowIndex) = probstr(full(TM.PpRetained(rowIndex)));
        end
        cells = [TM.Parameter,compose('%.5f',full(TM.Intercept)),compose('%.5f',full(TM.PosteriorSD)),ps];
        body = body+xmltable(["Parameter","Intercept at group X=0","Posterior SD","Pp retained"],cells);
        body = body+para('With a centered group covariate this intercept is the model-adjusted mean at the sample-average group coding, not necessarily an equally weighted mean of the two groups.',false);
        body = body+pagebreak()+para('Node order and prior coordinates',true)+xmltable(string(nodeTable.Properties.VariableNames),cellstrings(table2cell(nodeTable)));
        body = body+para('Saved analysis settings',true)+xmltable(string(settingsTable.Properties.VariableNames),cellstrings(table2cell(settingsTable)));
        body = body+pagebreak()+para('Subject-order and fit audit',true);
        cells = [string(full(subjectQCTable.PEBRow)),string(full(subjectQCTable.SubjectID)),subjectQCTable.Group,compose('%.6f',full(subjectQCTable.GroupX)),compose('%.3f',full(subjectQCTable.FreeEnergy)),compose('%.2f',full(subjectQCTable.FitR2Percent)),string(full(subjectQCTable.Modes)),string(full(subjectQCTable.FitArraysOK))];
        body = body+xmltable(["PEB row","Subject ID","Group","Group X","Free energy","Fit R2 %","Modes","Arrays valid"],cells);
        body = body+para('F values across different subjects are not competing-model evidence. Fit arrays passing checks does not establish physiological validity or convergence. Full filenames and any failure messages are saved in Extracted_Report_Values.mat.',false);
        body = body+pagebreak()+para('Interpretation and provenance notes',true);
        for rowIndex = 1:numel(notes)
            body = body+para(notes(rowIndex),false);
        end
        doc = string('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>')+body+ ...
            string('<w:sectPr><w:pgSz w:w="15840" w:h="12240" w:orient="landscape"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720"/></w:sectPr></w:body></w:document>');
        types = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
        rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
        writeutf8(fullfile(temporaryFolder,'[Content_Types].xml'),types);
        writeutf8(fullfile(temporaryFolder,'_rels','.rels'),rels);
        writeutf8(fullfile(temporaryFolder,'word','document.xml'),doc);
        zipFile = fullfile(temporaryFolder,'report.zip');
        zip(zipFile,{'[Content_Types].xml','_rels/.rels','word/document.xml'},temporaryFolder);
        copyfile(zipFile,path);

    catch cleanupError
        rmdir(temporaryFolder,'s');
        rethrow(cleanupError);
    end
    rmdir(temporaryFolder,'s');
end
function textValue = esc(textValue)
    textValue = string(textValue);
    textValue = replace(textValue,'&','&amp;');
    textValue = replace(textValue,'<','&lt;');
    textValue = replace(textValue,'>','&gt;');
    textValue = replace(textValue,'"','&quot;');
end
function textValues = cellstrings(cellValues)
    textValues = strings(size(cellValues));
    for valueIndex = 1:numel(cellValues)
        textValues(valueIndex) = valstr(cellValues{valueIndex});
    end
end
function paragraphXml = para(paragraphText,bold)
    boldXml = "";
    fontSize = 21;
    if bold
        boldXml = "<w:b/>";
        fontSize = 28;
    end
    paragraphXml = string('<w:p><w:pPr><w:spacing w:after="120"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>')+boldXml+ ...
        string('<w:sz w:val="')+string(fontSize)+string('"/></w:rPr><w:t xml:space="preserve">')+esc(paragraphText)+string('</w:t></w:r></w:p>');
end
function pageBreakXml = pagebreak()
    pageBreakXml = string('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
end
function tableXml = xmltable(headers,rows)
    numberOfColumns = numel(headers);
    columnWidth = floor(14400/numberOfColumns);
    border = '<w:top w:val="single" w:sz="4" w:color="B8C2CC"/><w:left w:val="single" w:sz="4" w:color="B8C2CC"/><w:bottom w:val="single" w:sz="4" w:color="B8C2CC"/><w:right w:val="single" w:sz="4" w:color="B8C2CC"/><w:insideH w:val="single" w:sz="4" w:color="B8C2CC"/><w:insideV w:val="single" w:sz="4" w:color="B8C2CC"/>';
    tableXml = string('<w:tbl><w:tblPr><w:tblW w:w="14400" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>')+string(border)+ ...
        string('</w:tblBorders><w:tblCellMar><w:top w:w="80" w:type="dxa"/><w:left w:w="90" w:type="dxa"/><w:bottom w:w="80" w:type="dxa"/><w:right w:w="90" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>');
    for columnIndex = 1:numberOfColumns
        tableXml = tableXml+'<w:gridCol w:w="'+string(columnWidth)+'"/>';
    end
    tableXml = tableXml+'</w:tblGrid>';
    allrows = [headers;rows];
    for rowIndex = 1:size(allrows,1)
        tableXml = tableXml+'<w:tr><w:trPr><w:cantSplit/>';
        if rowIndex == 1
            tableXml = tableXml+'<w:tblHeader/>';
        end;
        tableXml = tableXml+'</w:trPr>';
        for columnIndex = 1:numberOfColumns
            shadingXml = "";
            if rowIndex == 1
                shadingXml = "<w:shd w:fill=""E7EFF6""/>";
            end
            tableXml = tableXml+'<w:tc><w:tcPr><w:tcW w:w="'+string(columnWidth)+'" w:type="dxa"/>'+shadingXml+'</w:tcPr>'+para(allrows(rowIndex,columnIndex),false)+'</w:tc>';
        end
        tableXml = tableXml+'</w:tr>';
    end
    tableXml = tableXml+'</w:tbl>'+para('',false);
end
function writeutf8(filePath,textValue)
    fid = fopen(filePath,'w','n','UTF-8');
    if ~(fid >= 0)
        error('Cannot create %s',filePath);
    end
    try

        fprintf(fid,'%s',char(textValue));

    catch cleanupError
        fclose(fid);
        rethrow(cleanupError);
    end
    fclose(fid);
end
