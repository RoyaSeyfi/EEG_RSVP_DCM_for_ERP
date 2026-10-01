%% make_source_reconstruction_report.m
% Read-only QC and thesis reporting for SPM25 EEG head-model preparation.
%
% This script DOES NOT estimate a source inversion, modify an M/EEG file,
% or overwrite a DCM. It reads the 43 CaMspmeeg*.mat files after Head
% model specification and creates:
%   1) Source_Reconstruction_Tables.docx
%      Genuine editable Word tables (Office Open XML; no Word/ActiveX).
%   2) Figure_Source_Model_QC.png/.pdf/.fig
%      A representative three-panel head/source-model QC figure.
%   3) Source_Reconstruction_Methods_Results_FA.txt
%      A Persian reporting guide populated with the observed QC counts.
%   4) Source_Reconstruction_Subject_QC.mat
%      Detailed machine-readable QC retained outside the thesis tables.
%
% Scientific boundary:
% Head-model specification prepares the template anatomy, coregistration,
% cortical source mesh, and EEG forward model needed by DCM for ERP. It is
% not a conventional distributed source inversion and therefore does not
% provide group activation maps or source-amplitude significance tests.
%
% Official SPM references used for the reporting boundary and defaults:
% https://www.fil.ion.ucl.ac.uk/spm/docs/manual/meeg/eeg_imaging/
% https://www.fil.ion.ucl.ac.uk/spm/docs/tutorials/multi/source/

clearvars;
clc;
close all;
commandwindow;

%% ======================= ONLY EDIT THIS LINE ==========================
rootFolder = 'E:\Subjects44\SPM_MAT_DAT';
% ======================================================================

study.expectedFiles = 43;
study.expectedChannels = 63;
study.inversionIndex = 1;
study.expectedVertices = 8196;
study.datasetPattern = 'CaMspmeeg*.mat';
study.spatialModel = 'IMG';
study.dcmType = 'DCM for ERP';

if ~isfolder(rootFolder)
    error('Root folder does not exist: %s', rootFolder);
end

if isempty(which('spm'))
    error('SPM is not on the MATLAB path.');
end

spm('defaults','eeg');
spm_jobman('initcfg');

datasetFiles = dir(fullfile(rootFolder,'*',study.datasetPattern));
if ~(numel(datasetFiles) == study.expectedFiles)
    error('Expected %d CaMspmeeg MAT files, but found %d.', ...
        study.expectedFiles,numel(datasetFiles));
end


runStamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
outputFolder = fullfile(rootFolder, ...
    ['Source_Reconstruction_Report_' runStamp]);
figureFolder = fullfile(outputFolder,'figures');
mkdir(outputFolder);
mkdir(figureFolder);

fprintf('\nChecking %d source-model files...\n',numel(datasetFiles));

templateRow = emptyQCRow();
rows = repmat(templateRow,numel(datasetFiles),1);
representative = struct('available',false);

for fileNumber = 1:numel(datasetFiles)
    filePath = fullfile(datasetFiles(fileNumber).folder, ...
        datasetFiles(fileNumber).name);
    rows(fileNumber) = inspectOneDataset(filePath,study);

    fprintf('%02d/%02d  Subject %-4s  %s\n',fileNumber, ...
        numel(datasetFiles),char(rows(fileNumber).Subject), ...
        char(rows(fileNumber).Status));

    if ~representative.available && rows(fileNumber).Passed
        representative = collectRepresentativeGeometry(filePath, ...
            study.inversionIndex);
    end
end

subjectQC = struct2table(rows);
save(fullfile(outputFolder,'Source_Reconstruction_Subject_QC.mat'), ...
    'subjectQC','study');

summary = summariseQC(subjectQC,study);

docxFile = fullfile(outputFolder,'Source_Reconstruction_Tables.docx');
created = writeSourceDocx(docxFile,subjectQC,summary,study);
if ~(created)
    error('The DOCX tables could not be created.');
end


guideFile = fullfile(outputFolder, ...
    'Source_Reconstruction_Methods_Results_FA.txt');
writeReportingGuide(guideFile,summary,study);

if representative.available
    makeSourceModelFigure(representative,figureFolder,summary);
else
    warning(['No fully passing dataset was available for the representative ' ...
        'source-model figure. Tables and text were still created.']);
end

fprintf('\n========== SOURCE-MODEL REPORT COMPLETE ==========\n');
fprintf('Passing datasets: %d/%d\n',summary.Passed,summary.Found);
fprintf('DOCX tables: %s\n',docxFile);
fprintf('Reporting guide: %s\n',guideFile);
fprintf('Figures: %s\n',figureFolder);

try
    load handel.mat;
    sound(y,Fs);
catch
beep;
end


%% =========================== FUNCTIONS ================================
function row = inspectOneDataset(filePath,study)
    row = emptyQCRow();
    row.FilePath = string(filePath);
    [folderPath,fileName,fileExtension] = fileparts(filePath);
    [~,subjectFolder] = fileparts(folderPath);
    row.Subject = string(subjectFolder);
    row.FileName = string([fileName fileExtension]);

    issues = strings(0,1);

    try
        eegData = spm_eeg_load(filePath);
        row.Readable = true;
        row.NumberOfChannels = double(eegData.nchannels);
        row.SamplingRateHz = double(eegData.fsample);

        if row.NumberOfChannels ~= study.expectedChannels
            issues(end+1) = sprintf('Expected %d channels; found %d.', ...
                study.expectedChannels,row.NumberOfChannels); %#ok<AGROW>
        end

        [fidLabels,fidOK] = inspectFiducials(eegData);
        row.FiducialLabels = fidLabels;
        row.FiducialsOK = fidOK;
        if ~fidOK
            issues(end+1) = 'Standard fiducials are incomplete.'; %#ok<AGROW>
        end

        invEntry = getInversionEntry(eegData,study.inversionIndex);
        row.HasInversionEntry = true;

        if isfield(invEntry,'mesh')
            mesh = invEntry.mesh;
            anatomicalImage = readField(mesh,'sMRI','');
            row.AnatomicalTemplate = baseNameText(anatomicalImage);
            row.TemplateMesh = identifyTemplateMesh(mesh,anatomicalImage);

            [sourceVertices,~,sourceName] = readMesh( ...
                readField(mesh,'tess_ctx',[]),folderPath);
            row.SourceMesh = string(sourceName);
            row.SourceVertices = size(sourceVertices,1);
            row.MeshResolution = meshResolutionName(row.SourceVertices);

            [scalpVertices,~,~] = readMesh( ...
                readField(mesh,'tess_scalp',[]),folderPath);
            row.ScalpVertices = size(scalpVertices,1);
        else
            sourceVertices = [];
            scalpVertices = [];
            issues(end+1) = 'Mesh information is missing.'; %#ok<AGROW>
        end

        if ~row.TemplateMesh
            issues(end+1) = 'The anatomical mesh is not marked as template.'; %#ok<AGROW>
        end
        if row.SourceVertices ~= study.expectedVertices
            issues(end+1) = sprintf('Expected %d source vertices; found %d.', ...
                study.expectedVertices,row.SourceVertices); %#ok<AGROW>
        end

        [row.HasEEGCoregistration,sensorPositions,row.SensorCount] = ...
            inspectCoregistration(invEntry);
        if ~row.HasEEGCoregistration
            issues(end+1) = 'EEG coregistration is missing.'; %#ok<AGROW>
        elseif row.SensorCount ~= study.expectedChannels
            issues(end+1) = sprintf( ...
                'Expected %d coregistered EEG sensors; found %d.', ...
                study.expectedChannels,row.SensorCount); %#ok<AGROW>
        end

        [row.ForwardModel,row.EEGBEM] = inspectForwardModel(invEntry);
        if ~row.EEGBEM
            issues(end+1) = 'The EEG BEM forward model is missing.'; %#ok<AGROW>
        end

        if ~isempty(sensorPositions) && ~isempty(scalpVertices)
            distances = nearestVertexDistances(sensorPositions,scalpVertices);
            row.MedianSensorScalpDistanceMm = median(distances,'omitnan');
            row.MaximumSensorScalpDistanceMm = max(distances,[],'omitnan');
        end

        row.Passed = row.Readable && row.HasInversionEntry && ...
            row.TemplateMesh && row.SourceVertices == study.expectedVertices && ...
            row.FiducialsOK && row.HasEEGCoregistration && row.EEGBEM && ...
            row.NumberOfChannels == study.expectedChannels && ...
            row.SensorCount == study.expectedChannels;

        if row.Passed
            row.Status = "PASS";
            row.Message = "No required QC problem detected";
        else
            row.Status = "CHECK";
            row.Message = join(issues," | ");
        end

    catch errorInformation
        row.Status = "ERROR";
        row.Message = string(errorInformation.message);
    end
end


function isTemplate = identifyTemplateMesh(mesh,anatomicalImage)
% SPM versions do not all store an explicit mesh.template flag.  When it
% is absent, identify the canonical template from the saved structural-MRI
% path used by SPM (canonical/single_subj_T1).
    explicitFlag = readField(mesh,'template',[]);
    if ~isempty(explicitFlag)
        isTemplate = logicalScalar(explicitFlag);
        return;
    end

    imageText = lower(char(string(anatomicalImage)));
    isTemplate = contains(imageText,'single_subj_t1') || ...
        contains(imageText,[filesep 'canonical' filesep]) || ...
        contains(strrep(imageText,'\','/'),'/canonical/');
end


function row = emptyQCRow()
    row = struct;
    row.Subject = "";
    row.FileName = "";
    row.FilePath = "";
    row.Status = "NOT READ";
    row.Message = "";
    row.Readable = false;
    row.Passed = false;
    row.NumberOfChannels = NaN;
    row.SamplingRateHz = NaN;
    row.FiducialLabels = "";
    row.FiducialsOK = false;
    row.HasInversionEntry = false;
    row.TemplateMesh = false;
    row.AnatomicalTemplate = "";
    row.SourceMesh = "";
    row.MeshResolution = "";
    row.SourceVertices = NaN;
    row.ScalpVertices = NaN;
    row.HasEEGCoregistration = false;
    row.SensorCount = NaN;
    row.ForwardModel = "";
    row.EEGBEM = false;
    row.MedianSensorScalpDistanceMm = NaN;
    row.MaximumSensorScalpDistanceMm = NaN;
end


function [labelText,ok] = inspectFiducials(eegData)
    required = ["spmnas","spmlpa","spmrpa"];
    labels = strings(0,1);
    try
        fid = eegData.fiducials;
        if isfield(fid,'fid') && isfield(fid.fid,'label')
            labels = string(fid.fid.label(:));
        end
    catch
    end
    labelText = strjoin(labels,', ');
    ok = all(ismember(lower(required),lower(labels)));
end


function invEntry = getInversionEntry(eegData,index)
    invCollection = eegData.inv;
    if isempty(invCollection)
        error('D.inv is empty.');
    end

    if iscell(invCollection)
        if ~(numel(invCollection) >= index && ~isempty(invCollection{index}))
            error('Inversion entry %d is missing.',index);
        end

        invEntry = invCollection{index};
    else
        if ~(numel(invCollection) >= index)
            error('Inversion entry %d is missing.',index);
        end

        invEntry = invCollection(index);
    end
end


function [hasEEG,sensorPositions,sensorCount] = inspectCoregistration(invEntry)
    hasEEG = false;
    sensorPositions = [];
    sensorCount = NaN;
    if ~isfield(invEntry,'datareg') || isempty(invEntry.datareg)
        return;
    end

    for itemNumber = 1:numel(invEntry.datareg)
        item = invEntry.datareg(itemNumber);
        modality = upper(string(readField(item,'modality','')));
        if modality == "EEG"
            hasEEG = true;
            sensors = readField(item,'sensors',[]);
            sensorPositions = readSensorPositions(sensors);
            sensorCount = size(sensorPositions,1);
            return;
        end
    end
end


function positions = readSensorPositions(sensors)
    positions = [];
    if isempty(sensors) || ~isstruct(sensors)
        return;
    end
    if isfield(sensors,'chanpos') && ~isempty(sensors.chanpos)
        positions = double(sensors.chanpos);
    elseif isfield(sensors,'elecpos') && ~isempty(sensors.elecpos)
        positions = double(sensors.elecpos);
    elseif isfield(sensors,'pnt') && ~isempty(sensors.pnt)
        positions = double(sensors.pnt);
    end
    keepPosition = true(size(positions, 1), 1);
    for sensorNumber = 1:size(positions, 1)
        for coordinateNumber = 1:size(positions, 2)
            if ~isfinite(positions(sensorNumber, coordinateNumber))
                keepPosition(sensorNumber) = false;
            end
        end
    end
    positions = positions(keepPosition, :);
end


function [modelText,isBEM] = inspectForwardModel(invEntry)
    modelText = "Not recorded";
    isBEM = false;
    if ~isfield(invEntry,'forward') || isempty(invEntry.forward)
        return;
    end
    parts = strings(0,1);
    for itemNumber = 1:numel(invEntry.forward)
        item = invEntry.forward(itemNumber);
        modelName = string(readField(item,'voltype',''));
        modality = string(readField(item,'modality',''));
        if strlength(modelName) == 0
            modelName = string(readField(item,'type',''));
        end
        if strlength(modality) > 0
            parts(end+1) = modality + ": " + modelName; %#ok<AGROW>
        else
            parts(end+1) = modelName; %#ok<AGROW>
        end
        if contains(upper(modelName),'EEG') && contains(upper(modelName),'BEM')
            isBEM = true;
        end
    end
    modelText = strjoin(parts,' | ');
end


function summary = summariseQC(qcTable,study)
    summary = struct;
    summary.Expected = study.expectedFiles;
    summary.Found = height(qcTable);
    summary.Readable = sum(qcTable.Readable);
    summary.Passed = sum(qcTable.Passed);
    summary.TemplateMesh = sum(qcTable.TemplateMesh);
    summary.FiducialsOK = sum(qcTable.FiducialsOK);
    summary.Coregistration = sum(qcTable.HasEEGCoregistration);
    summary.EEGBEM = sum(qcTable.EEGBEM);
    summary.Normal8196 = sum(qcTable.SourceVertices == study.expectedVertices);
    summary.Channel63 = sum(qcTable.NumberOfChannels == study.expectedChannels);

    validChannels = qcTable.NumberOfChannels(isfinite(qcTable.NumberOfChannels));
    validSampling = qcTable.SamplingRateHz(isfinite(qcTable.SamplingRateHz));
    validMedianDistance = qcTable.MedianSensorScalpDistanceMm( ...
        isfinite(qcTable.MedianSensorScalpDistanceMm));
    validMaximumDistance = qcTable.MaximumSensorScalpDistanceMm( ...
        isfinite(qcTable.MaximumSensorScalpDistanceMm));

    summary.ChannelRange = finiteRangeText(validChannels,'%.0f');
    summary.SamplingRange = finiteRangeText(validSampling,'%.3f');
    summary.SensorDistanceMedian = finiteMedian(validMedianDistance);
    summary.SensorDistanceMaximum = finiteMaximum(validMaximumDistance);
end


function representative = collectRepresentativeGeometry(filePath,index)
    representative = struct('available',false);
    try
        eegData = spm_eeg_load(filePath);
        invEntry = getInversionEntry(eegData,index);
        mesh = invEntry.mesh;
        [representative.cortexVertices,representative.cortexFaces,~] = ...
            readMesh(readField(mesh,'tess_ctx',[]),eegData.path);
        [representative.scalpVertices,representative.scalpFaces,~] = ...
            readMesh(readField(mesh,'tess_scalp',[]),eegData.path);
        [hasEEG,representative.sensorPositions,~] = ...
            inspectCoregistration(invEntry);
        representative.fiducialPositions = readCoregisteredFiducials(invEntry);
        representative.fileName = string(eegData.fname);
        representative.available = hasEEG && ...
            ~isempty(representative.cortexVertices) && ...
            ~isempty(representative.cortexFaces) && ...
            ~isempty(representative.scalpVertices) && ...
            ~isempty(representative.scalpFaces) && ...
            ~isempty(representative.sensorPositions);
    catch
        representative.available = false;
    end
end


function points = readCoregisteredFiducials(invEntry)
    points = [];
    if ~isfield(invEntry,'datareg') || isempty(invEntry.datareg)
        return;
    end
    for itemNumber = 1:numel(invEntry.datareg)
        item = invEntry.datareg(itemNumber);
        if upper(string(readField(item,'modality',''))) ~= "EEG"
            continue;
        end
        fid = readField(item,'fid_eeg',[]);
        if isstruct(fid) && isfield(fid,'fid') && isfield(fid.fid,'pnt')
            points = double(fid.fid.pnt);
        end
        return;
    end
end


function [vertices,faces,meshName] = readMesh(meshValue,baseFolder)
    vertices = [];
    faces = [];
    meshName = 'Not recorded';
    if isempty(meshValue)
        return;
    end
    if iscell(meshValue)
        meshValue = meshValue{1};
    end

    if ischar(meshValue) || (isstring(meshValue) && isscalar(meshValue))
        meshFile = char(meshValue);
        if ~isfile(meshFile)
            candidate = fullfile(baseFolder,meshFile);
            if isfile(candidate)
                meshFile = candidate;
            end
        end
        if ~isfile(meshFile)
            return;
        end
        meshFileData = gifti(meshFile);
        vertices = double(meshFileData.vertices);
        faces = double(meshFileData.faces);
        [~,name,extension] = fileparts(meshFile);
        meshName = [name extension];
        return;
    end

    if isstruct(meshValue)
        if isfield(meshValue,'vertices')
            vertices = double(meshValue.vertices);
        elseif isfield(meshValue,'vert')
            vertices = double(meshValue.vert);
        elseif isfield(meshValue,'pnt')
            vertices = double(meshValue.pnt);
        end
        if isfield(meshValue,'faces')
            faces = double(meshValue.faces);
        elseif isfield(meshValue,'face')
            faces = double(meshValue.face);
        elseif isfield(meshValue,'tri')
            faces = double(meshValue.tri);
        end
        meshName = 'embedded mesh';
        return;
    end

    try
        vertices = double(meshValue.vertices);
        faces = double(meshValue.faces);
        meshName = 'GIfTI mesh';
    catch
    end
end


function value = readField(structure,fieldName,defaultValue)
    if isstruct(structure) && isfield(structure,fieldName)
        value = structure.(fieldName);
    else
        value = defaultValue;
    end
end


function value = logicalScalar(input)
    value = false;
    if isempty(input)
        return;
    end
    try
        value = logical(input(1));
    catch
    end
end


function output = baseNameText(input)
    output = "Not recorded";
    if isempty(input)
        return;
    end
    try
        [~,name,extension] = fileparts(char(string(input)));
        output = string([name extension]);
    catch
    end
end


function name = meshResolutionName(numberOfVertices)
    switch numberOfVertices
    case 5124
        name = "Coarse (5124 vertices)";
    case 8196
        name = "Normal (8196 vertices)";
    case 20484
        name = "Fine (20484 vertices)";
    otherwise
        name = string(sprintf('%d vertices',numberOfVertices));
    end
end


function distances = nearestVertexDistances(points, vertices)
    distances = nan(size(points, 1), 1);
    for pointNumber = 1:size(points, 1)
        squaredDistances = nan(size(vertices, 1), 1);
        for vertexNumber = 1:size(vertices, 1)
            differenceX = vertices(vertexNumber, 1) - points(pointNumber, 1);
            differenceY = vertices(vertexNumber, 2) - points(pointNumber, 2);
            differenceZ = vertices(vertexNumber, 3) - points(pointNumber, 3);
            squaredDistances(vertexNumber) = differenceX^2 + differenceY^2 + differenceZ^2;
        end
        distances(pointNumber) = sqrt(min(squaredDistances));
    end
end


function makeSourceModelFigure(representativeGeometry,outputFolder,summary)
    background = [1 1 1];
    scalpColour = [0.78 0.82 0.88];
    cortexColour = [0.38 0.64 0.72];
    sensorColour = [0.00 0.45 0.74];
    fiducialColour = [0.93 0.62 0.12];

    fig = figure('Color',background,'Position',[50 50 1650 900], ...
        'Visible','off');

    % Fixed axes positions reserve separate top and bottom strips so titles,
    % status text, and the scientific note cannot overlap the 3-D panels.
    ax1 = axes(fig,'Position',[0.035 0.205 0.295 0.600]);
    ax2 = axes(fig,'Position',[0.352 0.205 0.295 0.600]);
    ax3 = axes(fig,'Position',[0.670 0.205 0.295 0.600]);

    drawScalpSensors(ax1,representativeGeometry,scalpColour,sensorColour,fiducialColour,[0 90]);
    title(ax1,'A  EEG sensors and scalp: superior view', ...
        'FontName','Arial','FontSize',13,'FontWeight','bold');

    drawScalpSensors(ax2,representativeGeometry,scalpColour,sensorColour,fiducialColour,[90 0]);
    title(ax2,'B  EEG sensors and scalp: lateral view', ...
        'FontName','Arial','FontSize',13,'FontWeight','bold');

    patch(ax3,'Faces',representativeGeometry.cortexFaces,'Vertices',representativeGeometry.cortexVertices, ...
        'FaceColor',cortexColour,'EdgeColor','none','FaceLighting','gouraud', ...
        'AmbientStrength',0.42,'DiffuseStrength',0.70, ...
        'SpecularStrength',0.12);
    axis(ax3,'equal');
    axis(ax3,'vis3d');
    axis(ax3,'off');
    view(ax3,90,5);
    camlight(ax3,'headlight');
    material(ax3,'dull');
    title(ax3,sprintf('C  Cortical source mesh: %d vertices', ...
        size(representativeGeometry.cortexVertices,1)),'FontName','Arial','FontSize',13, ...
        'FontWeight','bold');

    annotation(fig,'textbox',[0.055 0.925 0.890 0.050], ...
        'String','EEG head model, coregistration, and cortical source space', ...
        'EdgeColor','none','HorizontalAlignment','center', ...
        'VerticalAlignment','middle','FontName','Arial','FontSize',19, ...
        'FontWeight','bold','Color',[0.08 0.12 0.18]);

    annotation(fig,'textbox',[0.075 0.855 0.850 0.045], ...
        'String',sprintf(['Representative dataset: %s   |   ' ...
        'complete QC: %d/%d datasets'],char(representativeGeometry.fileName), ...
        summary.Passed,summary.Found), ...
        'EdgeColor','none','HorizontalAlignment','center', ...
        'VerticalAlignment','middle','FontName','Arial','FontSize',11.5, ...
        'FontWeight','bold','Color',[0.18 0.28 0.40], ...
        'Interpreter','none');

    annotation(fig,'textbox',[0.075 0.045 0.850 0.095], ...
        'String',[ ...
        'Blue points: EEG sensors; gold points: fiducials; translucent gray: scalp; teal: cortical source mesh.  ' ...
        'This is a quality-control display of the template forward model, not a statistical source-activation map.'], ...
        'EdgeColor',[0.70 0.75 0.82],'LineWidth',1.0, ...
        'BackgroundColor',[0.96 0.97 0.99], ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'FontName','Arial','FontSize',10.5,'Color',[0.18 0.22 0.28], ...
        'Interpreter','none');

    baseName = 'Figure_Source_Model_QC';
    exportgraphics(fig,fullfile(outputFolder,[baseName '.png']), ...
        'Resolution',600,'BackgroundColor','white');
    exportgraphics(fig,fullfile(outputFolder,[baseName '.pdf']), ...
        'ContentType','vector','BackgroundColor','white');
    savefig(fig,fullfile(outputFolder,[baseName '.fig']));
    close(fig);
end


function drawScalpSensors(ax,representativeGeometry,scalpColour,sensorColour,fiducialColour,viewAngles)
    hold(ax,'on');
    patch(ax,'Faces',representativeGeometry.scalpFaces,'Vertices',representativeGeometry.scalpVertices, ...
        'FaceColor',scalpColour,'FaceAlpha',0.28,'EdgeColor','none', ...
        'FaceLighting','gouraud','AmbientStrength',0.45, ...
        'DiffuseStrength',0.62,'SpecularStrength',0.08);
    scatter3(ax,representativeGeometry.sensorPositions(:,1),representativeGeometry.sensorPositions(:,2), ...
        representativeGeometry.sensorPositions(:,3),28,sensorColour,'filled', ...
        'MarkerEdgeColor','white','LineWidth',0.55);
    if ~isempty(representativeGeometry.fiducialPositions)
        scatter3(ax,representativeGeometry.fiducialPositions(:,1),representativeGeometry.fiducialPositions(:,2), ...
            representativeGeometry.fiducialPositions(:,3),72,fiducialColour,'filled', ...
            'MarkerEdgeColor',[0.35 0.22 0.02],'LineWidth',0.8);
    end
    axis(ax,'equal');
    axis(ax,'vis3d');
    axis(ax,'off');
    view(ax,viewAngles(1),viewAngles(2));
    camlight(ax,'headlight');
    material(ax,'dull');
end


function writeReportingGuide(fileName,summary,study)
    fid = fopen(fileName,'w','n','UTF-8');
    if ~(fid ~= -1)
        error('Could not create reporting guide: %s',fileName);
    end

    try


        fprintf(fid,'راهنمای گزارش بازسازی منبع (Source reconstruction)\n\n');
        fprintf(fid,'بخش روش پژوهش\n');
        fprintf(fid,[ ...
            'برای آماده‌سازی مدل الکترومغناطیسی موردنیاز مدل‌سازی علّی پویا برای پاسخ‌های برانگیخته ' ...
            '(DCM for ERP)، مدل سر و مدل پیشرو برای %d مجموعه‌داده در نرم‌افزار (SPM) ایجاد شد. ' ...
            'به‌دلیل نبود تصویربرداری تشدید مغناطیسی ساختاری اختصاصی (MRI)، از قالب آناتومیکی استاندارد ' ...
            '(SPM) و مش قشری با وضوح معمول (Normal؛ %d رأس منبع) استفاده شد. موقعیت‌های استاندارد حسگرهای ' ...
            'الکتروانسفالوگرافی (EEG) و سه نقطه نشانه (Fiducial) شامل بینی (spmnas)، پیش‌گوشی چپ ' ...
            '(spmlpa) و پیش‌گوشی راست (spmrpa) به نقاط متناظر قالب نگاشت شدند. نقاط شکل سر ' ...
            '(Headshape points) استفاده نشدند. مدل رسانایی سر برای الکتروانسفالوگرافی از نوع مدل اجزای ' ...
            'مرزی (EEG BEM) و شاخص وارون‌سازی برابر ۱ بود. این مرحله مدل پیشرو لازم برای مدل فضایی ' ...
            '(IMG) در مدل علّی پویا (DCM) را فراهم کرد و یک وارون‌سازی توزیعی مستقل مانند روش پیشین‌های ' ...
            'تنک چندگانه (MSP) محسوب نمی‌شد.\n\n'], ...
            summary.Found,study.expectedVertices);

        fprintf(fid,'بخش نتایج\n');
        fprintf(fid,[ ...
            'مدل سر و مدل پیشرو در %d مورد از %d مجموعه‌داده معیارهای کامل کنترل کیفیت را برآورده کرد. ' ...
            'قالب آناتومیکی استاندارد در %d فایل، سه نقطه نشانه استاندارد در %d فایل، هم‌ثبت‌سازی ' ...
            'الکتروانسفالوگرافی (EEG) در %d فایل، مدل پیشرو اجزای مرزی (EEG BEM) در %d فایل و مش قشری ' ...
            '%d رأسی در %d فایل تأیید شد. این بررسی صرفاً موفقیت ' ...
            'آماده‌سازی مدل هندسی و پیشرو را نشان می‌دهد و نباید به‌عنوان شواهد فعال‌شدن یک ناحیه مغزی یا ' ...
            'تفاوت منبع میان گروه‌های تک‌زبانه و دوزبانه تفسیر شود.\n\n'], ...
            summary.Passed,summary.Found,summary.TemplateMesh,summary.FiducialsOK, ...
            summary.Coregistration,summary.EEGBEM,study.expectedVertices, ...
            summary.Normal8196);

        fprintf(fid,'مواردی که در این بخش نباید گزارش شوند\n');
        fprintf(fid,[ ...
            '- قدرت یا دامنه فعالیت منبع، چون وارون‌سازی توزیعی مستقل اجرا نشده است.\n' ...
            '- مقایسه آماری تک‌زبانه و دوزبانه در فضای منبع، چون این مرحله فقط مدل پیشرو است.\n' ...
            '- تفسیر مش ۸۱۹۶ رأسی به‌عنوان ۸۱۹۶ منبع فعال؛ این‌ها مکان‌های کاندید مدل هستند.\n' ...
            '- نتایج اتصال مؤثر؛ آن‌ها باید در بخش نتایج مدل علّی پویا (DCM) و مدل‌سازی تجربی بیزی (PEB) گزارش شوند.\n']);

    catch cleanupError
        fclose(fid);
        rethrow(cleanupError);
    end
    fclose(fid);
end


function created = writeSourceDocx(fileName,qcTable,summary,study)
    created = false;
    packageFolder = '';
    try
        [headers1,body1,note1] = makeMethodsTable(summary,study);
        [headers2,body2,note2] = makeResultsTable(summary,study);
        [headers3,body3,note3] = makeSubjectTable(qcTable);

        sections(1) = makeWordSection( ...
            'پارامترهای مدل سر، هم‌ثبت‌سازی و مدل پیشرو', ...
            headers1,body1,note1,10,[38 62],false); %#ok<AGROW>
        sections(2) = makeWordSection( ...
            'خلاصه کنترل کیفیت بازسازی منبع', ...
            headers2,body2,note2,10,[58 21 21],true); %#ok<AGROW>
        sections(3) = makeWordSection( ...
            'کنترل کیفیت هر آزمودنی', ...
            headers3,body3,note3,8.2,[7 8 7 8 10 10 10 12 8 20],true); %#ok<AGROW>

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

        zipFile = fullfile(packageFolder,'Source_Reconstruction_Tables.zip');
        zip(zipFile,{'[Content_Types].xml','_rels','word'},packageFolder);
        if ~isfile(zipFile)
            error('MATLAB did not create the temporary DOCX archive.');
        end


        if isfile(fileName)
            existingOutput = java.io.File(fileName);
            if ~(existingOutput.delete())
                error('Close the existing DOCX before running this script: %s',fileName);
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
    catch errorInformation
        warning('Could not create the DOCX source tables: %s',errorInformation.message);
    end

    if ~isempty(packageFolder) && isfolder(packageFolder)
        try
            rmdir(packageFolder,'s');
        catch cleanupError
            warning('Temporary DOCX folder could not be removed: %s', ...
                cleanupError.message);
        end
    end
end


function [headers,body,note] = makeMethodsTable(summary,study)
    headers = {'مولفه','مشخصات'};
    body = { ...
        'کاربرد مرحله','آماده‌سازی مدل پیشرو برای مدل علّی پویای پاسخ برانگیخته (DCM for ERP) با مدل فضایی (IMG)'; ...
        'فایل‌های ورودی',sprintf('%d فایل با الگوی %s', ...
        summary.Found,study.datasetPattern); ...
        'نرم‌افزار',char(string(spm('Ver'))); ...
        'نوع داده','الکتروانسفالوگرافی (EEG)'; ...
        'شاخص وارون‌سازی (Inversion index)',sprintf('%d',study.inversionIndex); ...
        'منبع مش (Mesh source)','قالب استاندارد (Template)'; ...
        'قالب آناتومیکی','تصویر T1 استاندارد تک‌آزمودنی SPM (single_subj_T1)'; ...
        'وضوح مش','معمول (Normal)'; ...
        'فضای منبع',sprintf('مش قشری با %d رأس کاندید',study.expectedVertices); ...
        'موقعیت حسگرها','موقعیت‌های پیش‌فرض استاندارد الکتروانسفالوگرافی (EEG) در نرم‌افزار (SPM)، بر اساس نام کانال‌های موجود'; ...
        'نقاط نشانه (Fiducials)','بینی (spmnas)، پیش‌گوشی چپ (spmlpa) و پیش‌گوشی راست (spmrpa)؛ متناظر با (nas)، (lpa) و (rpa)'; ...
        'نقاط شکل سر (Headshape)','استفاده نشد'; ...
        'مدل سر الکتروانسفالوگرافی (EEG)','مدل اجزای مرزی (EEG BEM)'; ...
        'مدل مگنتوانسفالوگرافی (MEG)','در تحلیل الکتروانسفالوگرافی (EEG) استفاده نشد'};
    note = ['یادداشت: این جدول در بخش روش پژوهش قرار می‌گیرد. ساخت مدل سر و ' ...
        'مدل پیشرو با وارون‌سازی مستقل منبع یا آزمون آماری فعالیت منبع یکسان نیست.'];
end


function [headers,body,note] = makeResultsTable(summary,study)
    headers = {'شاخص کنترل کیفیت','تعداد','نتیجه'};
    body = { ...
        'فایل‌های مورد انتظار و یافت‌شده',sprintf('%d / %d', ...
        summary.Found,summary.Expected),passText(summary.Found == summary.Expected); ...
        'فایل‌های قابل خواندن در نرم‌افزار (SPM)',sprintf('%d / %d', ...
        summary.Readable,summary.Found),passText(summary.Readable == summary.Found); ...
        'تعداد کانال مورد انتظار',sprintf('%d / %d', ...
        summary.Channel63,summary.Found),passText(summary.Channel63 == summary.Found); ...
        'قالب آناتومیکی استاندارد',sprintf('%d / %d', ...
        summary.TemplateMesh,summary.Found),passText(summary.TemplateMesh == summary.Found); ...
        'سه نقطه نشانه استاندارد',sprintf('%d / %d', ...
        summary.FiducialsOK,summary.Found),passText(summary.FiducialsOK == summary.Found); ...
        'هم‌ثبت‌سازی الکتروانسفالوگرافی (EEG)',sprintf('%d / %d', ...
        summary.Coregistration,summary.Found),passText(summary.Coregistration == summary.Found); ...
        'مدل پیشرو اجزای مرزی (EEG BEM)',sprintf('%d / %d', ...
        summary.EEGBEM,summary.Found),passText(summary.EEGBEM == summary.Found); ...
        sprintf('مش قشری %d رأسی',study.expectedVertices),sprintf('%d / %d', ...
        summary.Normal8196,summary.Found),passText(summary.Normal8196 == summary.Found); ...
        'برآورده‌شدن همه معیارها',sprintf('%d / %d', ...
        summary.Passed,summary.Found),passText(summary.Passed == summary.Found); ...
        'دامنه تعداد کانال‌ها',summary.ChannelRange,'توصیفی'; ...
        'دامنه نرخ نمونه‌برداری برحسب هرتز (Hz)',summary.SamplingRange,'توصیفی'; ...
        'میانه فاصله حسگر تا نزدیک‌ترین رأس پوست سر برحسب میلی‌متر (mm)', ...
        formatOptionalNumber(summary.SensorDistanceMedian,3),'کنترل هندسی توصیفی'; ...
        'بیشینه فاصله حسگر تا نزدیک‌ترین رأس پوست سر برحسب میلی‌متر (mm)', ...
        formatOptionalNumber(summary.SensorDistanceMaximum,3),'کنترل هندسی توصیفی'};
    note = ['یادداشت: این جدول در بخش نتایج قرار می‌گیرد و فقط کامل‌بودن مدل ' ...
        'هندسی و پیشرو را گزارش می‌کند. این شمارش‌ها آزمون معنی‌داری فعالیت ' ...
        'قشری یا مقایسه بین گروهی نیستند.'];
end


function [headers,body,note] = makeSubjectTable(qcTable)
    headers = {'آزمودنی','وضعیت','کانال','هرتز (Hz)','رأس منبع', ...
        'نقاط نشانه','هم‌ثبت‌سازی','مدل پیشرو','قالب','پیام'};
    body = cell(height(qcTable),numel(headers));
    for row = 1:height(qcTable)
        body{row,1} = char(qcTable.Subject(row));
        body{row,2} = char(qcTable.Status(row));
        body{row,3} = formatOptionalNumber(qcTable.NumberOfChannels(row),0);
        body{row,4} = formatOptionalNumber(qcTable.SamplingRateHz(row),1);
        body{row,5} = formatOptionalNumber(qcTable.SourceVertices(row),0);
        body{row,6} = yesNo(qcTable.FiducialsOK(row));
        body{row,7} = yesNo(qcTable.HasEEGCoregistration(row));
        body{row,8} = char(qcTable.ForwardModel(row));
        body{row,9} = yesNo(qcTable.TemplateMesh(row));
        body{row,10} = char(qcTable.Message(row));
    end
    note = ['یادداشت: این جدول برای پیوست یا کنترل کیفیت تکمیلی مناسب است. ' ...
        'وضعیت تأیید (PASS) یعنی تمام معیارهای ازپیش‌تعیین‌شده این اسکریپت تأیید شده‌اند.'];
end


function output = passText(condition)
    if condition
        output = 'تأیید شد';
    else
        output = 'نیازمند بررسی';
    end
end


function output = yesNo(condition)
    if condition
        output = 'بله';
    else
        output = 'خیر';
    end
end


function textValue = formatOptionalNumber(value,decimalPlaces)
    if isempty(value) || ~isfinite(value)
        textValue = 'ثبت نشده';
    else
        textValue = sprintf(['%.' num2str(decimalPlaces) 'f'],value);
    end
end


function textValue = finiteRangeText(values,formatText)
    if isempty(values)
        textValue = 'ثبت نشده';
    elseif min(values) == max(values)
        textValue = sprintf(formatText,min(values));
    else
        textValue = sprintf([formatText ' تا ' formatText], ...
            min(values),max(values));
    end
end


function value = finiteMedian(values)
    if isempty(values)
        value = NaN;
    else
        value = median(values);
    end
end


function value = finiteMaximum(values)
    if isempty(values)
        value = NaN;
    else
        value = max(values);
    end
end


function section = makeWordSection(titleText,headers,body,noteText, ...
    fontSize,columnWidths,pageBreakBefore)
    section = struct('title',titleText,'headers',{headers},'body',{body}, ...
        'note',noteText,'fontSize',fontSize,'columnWidths',columnWidths, ...
        'pageBreakBefore',pageBreakBefore);
end


function xml = makeDocxDocumentXml(sections)
    parts = cell(1,3+3*numel(sections));
    part = 0;
    part = part+1;
    parts{part} = [ ...
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' ...
        '<w:document xmlns:w="http://schemas.openxmlformats.org/' ...
        'wordprocessingml/2006/main"><w:body>'];
    part = part+1;
    parts{part} = makeWordParagraphXml( ...
        'جداول مدل سر، هم‌ثبت‌سازی و مدل پیشرو',16,true,'center',0,220,false);
    part = part+1;
    parts{part} = makeWordParagraphXml( ...
        ['این سند شامل پارامترهای روش، خلاصه نتایج کنترل کیفیت و جدول ' ...
        'آزمودنی‌ها برای مرحله بازسازی منبع موردنیاز مدل علّی پویای پاسخ برانگیخته (DCM for ERP) است.'], ...
        11,false,'right',0,220,false);

    for sectionIndex = 1:numel(sections)
        section = sections(sectionIndex);
        part = part+1;
        parts{part} = makeWordParagraphXml(section.title,13,true,'right', ...
            0,120,section.pageBreakBefore);
        part = part+1;
        parts{part} = makeWordTableXml(section.headers,section.body, ...
            section.fontSize,section.columnWidths);
        part = part+1;
        parts{part} = makeWordParagraphXml(section.note,9,false,'right', ...
            90,200,false);
    end

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
        error('Word table body does not match its header width.');
    end

    if ~(numel(columnWidths) == numberOfColumns)
        error('Word table column-width vector is incorrect.');
    end

    contentWidth = 15398;
    columnWidths = double(columnWidths(:)');
    columnTwips = round(contentWidth*columnWidths/sum(columnWidths));
    columnTwips(end) = columnTwips(end)+contentWidth-sum(columnTwips);

    parts = cell(1,4+(size(body,1)+1)*(numberOfColumns+1));
    part = 0;
    part = part+1;
    parts{part} = [ ...
        '<w:tbl><w:tblPr><w:bidiVisual/><w:tblW w:w="15398" w:type="dxa"/>' ...
        '<w:tblBorders><w:top w:val="single" w:sz="4" w:color="D9D9D9"/>' ...
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
            columnTwips(column))]; %#ok<AGROW>
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

    if isHeader || ~isempty(regexp(textValue,'[\x{0600}-\x{06FF}]','once'))
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
        '<w:vAlign w:val="center"/></w:tcPr><w:p><w:pPr>%s' ...
        '<w:spacing w:before="0" w:after="0" w:line="240" ' ...
        'w:lineRule="auto"/><w:jc w:val="center"/></w:pPr><w:r><w:rPr>' ...
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="B Nazanin"/>' ...
        '%s<w:color w:val="%s"/><w:sz w:val="%d"/><w:szCs w:val="%d"/>%s' ...
        '</w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p></w:tc>'], ...
        widthTwips,fillColor,bidiXml,boldXml,textColor,fontHalfPoints, ...
        fontHalfPoints,rtlXml,escapeWordXml(textValue));
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
        '<w:p><w:pPr>%s<w:bidi/><w:spacing w:before="%d" w:after="%d" ' ...
        'w:line="276" w:lineRule="auto"/><w:jc w:val="%s"/></w:pPr>' ...
        '<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" ' ...
        'w:cs="B Nazanin"/>%s<w:color w:val="000000"/>' ...
        '<w:sz w:val="%d"/><w:szCs w:val="%d"/><w:rtl/></w:rPr>' ...
        '<w:t xml:space="preserve">%s</w:t></w:r></w:p>'], ...
        pageBreakXml,spaceBefore,spaceAfter,alignment,boldXml, ...
        fontHalfPoints,fontHalfPoints,escapeWordXml(textValue));
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
