function outDir = make_BrainNet_DCM_ERP_files(reportFile,transposeForViewer)
% Export two BrainNet Viewer figures' INPUT FILES from the verified DCM report.
% Figure 1: six original DCM MNI source priors (.node; NO .edge).
% Figure 2: directed retained PEB/BMA group effects (.node + .edge).
% No analysis is re-estimated and no source coordinate is moved.
%
% Run in MATLAB:
%   outDir = make_BrainNet_DCM_ERP_files;
% Or provide Extracted_Report_Values.mat as a full path.
% If the one-edge calibration points backwards in your installed BrainNet:
%   outDir = make_BrainNet_DCM_ERP_files([],true);

    if nargin < 2 || isempty(transposeForViewer)
        transposeForViewer = false;
    end
    if ~(islogical(transposeForViewer) && isscalar(transposeForViewer))
        error('transposeForViewer must be logical true or false.');
    end


    if nargin < 1 || isempty(reportFile)
        root = 'E:\Subjects44\SPM_MAT_DAT\GCM_DCM';
        matches = dir(fullfile(root,'DCM_ERP_Report_*','Extracted_Report_Values.mat'));
        if isempty(matches)
            error(['No Extracted_Report_Values.mat found. ' ...
                'Supply its full path explicitly.']);
        end

        [~,latestReportIndex] = max([matches.datenum]);
        reportFile = fullfile(matches(latestReportIndex).folder,matches(latestReportIndex).name);
    end
    if ~isfile(reportFile)
        error('Report MAT missing: %s',reportFile);
    end

    savedReport = load(reportFile,'T','NodeTable','cfg');
    if ~all(isfield(savedReport,{'T','NodeTable','cfg'}))
        error('The report must contain T, NodeTable and cfg.');
    end

    connectionTable = savedReport.T;
    nodeTable = savedReport.NodeTable;
    if ~(istable(connectionTable) && istable(nodeTable) && height(nodeTable) == 6 && height(connectionTable) == 14)
        error('Expected the six-region, 14-connection DCM ERP report.');
    end

    if ~all(ismember({'Index','SavedName','IntendedRole', ...
        'MNI_X','MNI_Y','MNI_Z'},nodeTable.Properties.VariableNames))
        error('NodeTable fields do not match the reporting script.');
    end

    if ~all(ismember({'Parameter','Family','Source','Target', ...
        'MonoMinusBi','PpRetained','Strong'},connectionTable.Properties.VariableNames))
        error('Connection table fields do not match the reporting script.');
    end

    if ~isfield(savedReport.cfg,'Threshold')
        error('Missing saved posterior threshold.');
    end

    if ~isequal(full(double(nodeTable.Index(:))),(1:6)')
        error('NodeTable is not in original DCM source order.');
    end


    nodeNames = strtrim(string(nodeTable.SavedName(:)));
    roles = strtrim(string(nodeTable.IntendedRole(:)));
    expectedRoles = ["L_EVC";"R_EVC";"L_LOC";"R_LOC";"L_IT";"R_IT"];
    if ~(isequal(roles,expectedRoles) && numel(unique(lower(nodeNames))) == 6)
        error('Node order/roles differ; verify the saved DCM before exporting.');
    end

    coords = full(double([nodeTable.MNI_X(:),nodeTable.MNI_Y(:),nodeTable.MNI_Z(:)]));
    if ~(isequal(size(coords),[6,3]) && all(isfinite(coords(:))))
        error('Invalid original MNI coordinates.');
    end

    if ~(all(coords([1,3,5],1)<0) && all(coords([2,4,6],1)>0))
        error('Unexpected left/right coordinate signs.');
    end

    threshold = full(double(savedReport.cfg.Threshold));
    if ~(isscalar(threshold) && isfinite(threshold) && ...
        threshold>.5 && threshold<1)
        error('Invalid saved threshold.');
    end

    posterior = full(double(connectionTable.PpRetained(:)));
    contrast = full(double(connectionTable.MonoMinusBi(:)));
    if ~(all(isfinite(posterior)) && all(posterior >= 0 & posterior <= 1) && ...
        all(isfinite(contrast)))
        error('Invalid group results.');
    end

    retained = posterior>threshold;
    if ~isequal(retained,logical(full(connectionTable.Strong(:))))
        error('Retained edge flags disagree with the saved threshold.');
    end


    % Read exact saved parameter names to check SPM's A{family}(target,source).
    [isSource,sourceIndex] = ismember(string(connectionTable.Source(:)),nodeNames);
    [isTarget,targetIndex] = ismember(string(connectionTable.Target(:)),nodeNames);
    if ~all(isSource & isTarget & sourceIndex ~= targetIndex)
        error('Source/target name mismatch.');
    end

    expectedFamily = ["Forward","Backward","Lateral"];
    familyNumber = zeros(height(connectionTable),1);
    for edgeIndex = 1:height(connectionTable)
        token = regexp(char(string(connectionTable.Parameter(edgeIndex))), ...
            '^A\{([123])\}\(([1-6]),([1-6])\)$','tokens','once');
        if isempty(token)
            error('Unexpected DCM parameter: %s',string(connectionTable.Parameter(edgeIndex)));
        end

        familyNumber(edgeIndex) = str2double(token{1});
        if ~(str2double(token{2}) == targetIndex(edgeIndex) && str2double(token{3}) == sourceIndex(edgeIndex))
            error('SPM target/source mismatch in %s.',string(connectionTable.Parameter(edgeIndex)));
        end

        if ~(string(connectionTable.Family(edgeIndex)) == expectedFamily(familyNumber(edgeIndex)))
            error('Connection family mismatch in %s.',string(connectionTable.Parameter(edgeIndex)));
        end

    end
    countByPair = zeros(6, 6);
    for edgeIndex = 1:height(connectionTable)
        if retained(edgeIndex)
            sourceNumber = sourceIndex(edgeIndex);
            targetNumber = targetIndex(edgeIndex);
            countByPair(sourceNumber, targetNumber) = ...
                countByPair(sourceNumber, targetNumber) + 1;
        end
    end
    if ~all(countByPair(:) <= 1)
        error(['Two retained parameter families share the ' ...
            'same directed pair; one .edge cell cannot encode both.']);
    end

    if ~all(contrast(retained) ~= 0)
        error('A retained effect has zero sign and cannot be assigned a group color.');
    end


    stamp = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
    outDir = fullfile(fileparts(reportFile),['BrainNet_ERP_Inputs_' stamp]);
    mkdir(outDir);

    % BrainNet .node: X Y Z colorIndex nodeSize label (NO header).
    nodeFile = fullfile(outDir,'01_Original_MNI_Six_Nodes.node');
    fid = fopen(nodeFile,'wt');
    if ~(fid >= 0)
        error('Unable to create .node file.');
    end

    for edgeIndex = 1:6
        label = regexprep(char(nodeNames(edgeIndex)),'\s+','_');
        if ~(~isempty(label) && ~contains(label,'#'))
            error('Node label is not valid for BrainNet.');
        end

        fprintf(fid,'%.4f\t%.4f\t%.4f\t%d\t%d\t%s\n', ...
            coords(edgeIndex,1),coords(edgeIndex,2),coords(edgeIndex,3), ...
            1+double(coords(edgeIndex,1)>0),3,label);
    end
    if ~(fclose(fid) == 0)
        error('Could not finish the .node file.');
    end


    % BrainNet adjacency convention: ROW = arrow tail/source;
    % COLUMN = arrow tip/target. This is the TRANSPOSE of SPM's A indexing.
    both = zeros(6);
    signedGroup = zeros(6);
    mono = zeros(6);
    bi = zeros(6);
    customColor = zeros(6);
    for edgeIndex = 1:height(connectionTable)
        if ~retained(edgeIndex)
            continue;
        end
        sourceNumber = sourceIndex(edgeIndex);
        targetNumber = targetIndex(edgeIndex);
        both(sourceNumber,targetNumber) = 1;
        if contrast(edgeIndex)>0
            mono(sourceNumber,targetNumber) = 1;
            customColor(sourceNumber,targetNumber) = 1;
            signedGroup(sourceNumber,targetNumber) = 1;
        else
            bi(sourceNumber,targetNumber) = 1;
            customColor(sourceNumber,targetNumber) = 2;
            signedGroup(sourceNumber,targetNumber) = -1;
        end
    end
    if transposeForViewer
        both = both';
        mono = mono';
        bi = bi';
        signedGroup = signedGroup';
        customColor = customColor';
    end
    if ~(isequal(both,mono+bi) && nnz(both) == sum(retained))
        error('Edge matrix audit failed.');
    end

    write_edge(outDir,'02_Retained_Directed_All.edge',both);
    % Recommended for the two-color panel: keep signed +/-1 and choose
    % Edge > Color > Threshold 0, with Color absolute-value OFF.
    writematrix(signedGroup,fullfile(outDir,'02b_Retained_Group_Colors.edge'), ...
        'FileType','text','Delimiter','tab');
    write_edge(outDir,'03_Retained_Monolingual_Stronger.edge',mono);
    write_edge(outDir,'04_Retained_Bilingual_Stronger.edge',bi);
    writematrix(customColor,fullfile(outDir,'05_Edge_Color_Index.txt'), ...
        'FileType','text','Delimiter','tab');

    % Direction calibration: for this one-edge matrix, 1 -> 3 must appear.
    calibration = zeros(6);
    if transposeForViewer
        calibration(3,1) = 1;
    else
        calibration(1,3) = 1;
    end
    write_edge(outDir,'00_Check_Direction_1_to_3.edge',calibration);

    audit = table((1:height(connectionTable))',string(connectionTable.Parameter(:)), ...
        string(connectionTable.Family(:)),sourceIndex,targetIndex,nodeNames(sourceIndex),nodeNames(targetIndex), ...
        contrast,posterior,retained, ...
        'VariableNames',{'Row','SPM_Parameter','Family','SourceIndex', ...
        'TargetIndex','Source','Target','MonolingualMinusBilingual', ...
        'BMA_InclusionProbability','Retained'});
    writetable(audit,fullfile(outDir,'06_Direction_And_Group_Audit.csv'));
    writetable(nodeTable,fullfile(outDir,'07_Original_MNI_Node_Audit.csv'));

    fprintf('Source report: %s\n',reportFile);
    fprintf('BrainNet inputs: %s\n',outDir);
    fprintf('Six nodes; %d/%d retained directed group effects at Pp > %.2f\n', ...
        nnz(both),height(connectionTable),threshold);
    fprintf('Transpose for this BrainNet installation: %d\n',transposeForViewer);
    fprintf('Monolingual stronger: %d; bilingual stronger: %d\n',nnz(mono),nnz(bi));
    disp(audit(audit.Retained,{'SPM_Parameter','Source','Target', ...
        'MonolingualMinusBilingual','BMA_InclusionProbability'}));
end

function write_edge(outDir,name,edgeMatrix)
    if ~(isequal(size(edgeMatrix),[6 6]) && all(diag(edgeMatrix) == 0) && ...
        all(ismember(edgeMatrix(:),[0 1])))
        error('Invalid directed edge matrix.');
    end

    writematrix(edgeMatrix,fullfile(outDir,name),'FileType','text','Delimiter','tab');
end
