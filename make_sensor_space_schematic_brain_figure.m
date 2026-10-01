%% make_sensor_space_schematic_brain_figure.m
% Creates ONLY two publication-style schematic brain figures:
%   1) Monolingual > Bilingual
%   2) Bilingual > Monolingual
%
% Each figure contains left and right LATERAL cortical-surface views, like
% the upper brain panels in a neuroimaging article. No time-course,
% boxplot, scalp map, table, or other figure is produced by this script.
%
% IMPORTANT SCIENTIFIC LIMITATION
% The coloured mark is a graphical summary of a SENSOR-SPACE result. It is
% NOT source localisation, and it must not be interpreted as a cortical
% generator or an MNI-localised activation. The cortical surface is only
% an illustrative backdrop.

clearvars;
clc;

%% ======================= ONLY EDIT THIS LINE ==========================
resultsDir = 'E:\Subjects44\SPM_MAT_DAT\results_of_smooth';
% ======================================================================

contrastSpec(1).name = "Monolingual > Bilingual";
contrastSpec(1).weights = [1; -1];

contrastSpec(2).name = "Bilingual > Monolingual";
contrastSpec(2).weights = [-1; 1];

voxelFWE = 0.05;
extentThreshold = 0;

%% Load the estimated second-level model
spmMatFile = fullfile(resultsDir, 'SPM.mat');
if ~isfile(spmMatFile)
    error('SPM.mat was not found: %s', spmMatFile);
end


spm('defaults', 'eeg');
spm_jobman('initcfg');

loadedModel = load(spmMatFile, 'SPM');
SPM = loadedModel.SPM;
if ~(isfield(SPM, 'xVol') && isfield(SPM.xVol, 'S'))
    error('The second-level model has not been estimated.');
end

if ~(isfield(SPM, 'xCon') && ~isempty(SPM.xCon))
    error('No contrasts were found in SPM.mat.');
end


%% Locate both contrasts by their numerical weights
contrastIndices = nan(1, 2);

for contrastNumber = 1:2
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
        error('Contrast [%s] was not found.', num2str(wanted'));
    end

    contrastIndices(contrastNumber) = matching(1);

    if numel(matching) > 1
        warning(['Duplicate contrast [%s] exists at indices %s. ' ...
            'Only index %d is used.'], ...
            num2str(wanted'), mat2str(matching), matching(1));
    end
end

%% Evaluate the two contrasts at the same Results threshold
originalFolder = pwd;
try

    result = repmat(struct(), 1, 2);

    for contrastNumber = 1:2
        xSPMinput = struct;
        xSPMinput.swd = resultsDir;
        xSPMinput.title = char(contrastSpec(contrastNumber).name);
        xSPMinput.Ic = contrastIndices(contrastNumber);
        xSPMinput.n = 1;
        xSPMinput.Im = [];
        xSPMinput.pm = [];
        xSPMinput.Ex = [];
        xSPMinput.u = voxelFWE;
        xSPMinput.k = extentThreshold;
        xSPMinput.thresDesc = 'FWE';

        [~, xSPM] = spm_getSPM(xSPMinput);
        if isempty(xSPM)
            error('SPM could not evaluate contrast %d.', contrastNumber);
        end


        TabDat = spm_list('Table', xSPM, Inf, 8);
        result(contrastNumber).hasSignificantVoxels = ~isempty(TabDat.dat);
        result(contrastNumber).thresholdT = double(xSPM.u);
        result(contrastNumber).residualDf = double(xSPM.df(2));

        if result(contrastNumber).hasSignificantVoxels
            result(contrastNumber).clusterPFWE = cellNumber(TabDat.dat{1,3});
            result(contrastNumber).clusterSize = cellNumber(TabDat.dat{1,5});
            result(contrastNumber).peakPFWE = cellNumber(TabDat.dat{1,7});
            result(contrastNumber).peakT = cellNumber(TabDat.dat{1,9});
            result(contrastNumber).peakZ = cellNumber(TabDat.dat{1,10});
            coordinate = double(TabDat.dat{1,12}(:));
            result(contrastNumber).peakWorld = coordinate(1:3);
        else
            result(contrastNumber).clusterPFWE = NaN;
            result(contrastNumber).clusterSize = 0;
            result(contrastNumber).peakPFWE = NaN;
            result(contrastNumber).peakT = NaN;
            result(contrastNumber).peakZ = NaN;
            result(contrastNumber).peakWorld = [NaN; NaN; NaN];
        end
    end

    %% Load SPM's canonical cortical surface
    % This gives a genuine lateral cortical-surface VIEW, but the coloured
    % sensor-space marker remains illustrative and is not source reconstruction.
    [brainVertices, brainFaces, meshName] = loadCanonicalCortex(spm('Dir'));

    %% Output folder
    runStamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    outputDir = fullfile(resultsDir, ...
        ['lateral_schematic_brains_' runStamp]);
    mkdir(outputDir);

    %% Create exactly one figure for each contrast
    for contrastNumber = 1:2
        createLateralFigure(brainVertices, brainFaces, ...
            contrastSpec(contrastNumber), result(contrastNumber), ...
            meshName, outputDir, contrastNumber, voxelFWE, extentThreshold);
    end

    fprintf('\n========== LATERAL SCHEMATIC FIGURES COMPLETE ==========\n');
    fprintf('Two figures were saved in:\n%s\n', outputDir);
    fprintf(['Only schematic lateral brain figures were produced. ' ...
        'No other plots or tables were created.\n']);

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
function createLateralFigure(vertices, faces, contrastInfo, resultInfo, ...
    meshName, outputDir, contrastNumber, voxelFWE, extentThreshold)

    background = [0.025 0.035 0.055];
    panelColour = [0.055 0.070 0.095];
    whiteText = [0.96 0.97 0.99];
    softText = [0.72 0.77 0.84];

    fig = figure('Color', background, 'Position', [70 70 1500 780], ...
        'InvertHardcopy', 'off');

    % Fixed axes positions deliberately reserve independent top and bottom
    % strips, preventing titles, statistics, and scientific notes overlapping.
    leftAx = axes(fig, 'Position', [0.045 0.185 0.435 0.620], ...
        'Color', panelColour);
    rightAx = axes(fig, 'Position', [0.520 0.185 0.435 0.620], ...
        'Color', panelColour);

    drawLateralBrain(leftAx, vertices, faces, -1, resultInfo);
    drawLateralBrain(rightAx, vertices, faces, +1, resultInfo);

    text(leftAx, 0.04, 0.94, 'L', 'Units', 'normalized', ...
        'Color', whiteText, 'FontName', 'Arial', 'FontSize', 15, ...
        'FontWeight', 'bold', 'HorizontalAlignment', 'left');
    text(rightAx, 0.96, 0.94, 'R', 'Units', 'normalized', ...
        'Color', whiteText, 'FontName', 'Arial', 'FontSize', 15, ...
        'FontWeight', 'bold', 'HorizontalAlignment', 'right');

    annotation(fig, 'textbox', [0.06 0.915 0.88 0.055], ...
        'String', char(contrastInfo.name), ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'Color', whiteText, ...
        'FontName', 'Arial', 'FontSize', 18, 'FontWeight', 'bold', ...
        'Interpreter', 'none');

    if resultInfo.hasSignificantVoxels
        statusText = sprintf([ ...
            'Sensor-space effect at %.0f ms  |  T(%.0f) = %.2f, Z = %.2f, ' ...
            'peak pFWE = %.3f, k = %.0f'], ...
            resultInfo.peakWorld(3), resultInfo.residualDf, ...
            resultInfo.peakT, resultInfo.peakZ, ...
            resultInfo.peakPFWE, resultInfo.clusterSize);
        statusColour = [1.00 0.78 0.25];
    else
        statusText = sprintf([ ...
            'No voxel-level FWE-significant sensor-space effect ' ...
            '(pFWE < %.2f, k = %d)'], voxelFWE, extentThreshold);
        statusColour = [0.48 0.80 0.96];
    end

    annotation(fig, 'textbox', [0.08 0.842 0.84 0.050], ...
        'String', statusText, 'EdgeColor', 'none', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'Color', statusColour, 'FontName', 'Arial', ...
        'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none');

    annotation(fig, 'textbox', [0.07 0.050 0.86 0.085], ...
        'String', [ ...
        'SCHEMATIC SENSOR-SPACE DISPLAY -- NOT SOURCE LOCALISATION.  ' ...
        'The cortical surfaces are illustrative backdrops; the coloured ' ...
        'mark does not identify a cortical generator or an MNI location.'], ...
        'EdgeColor', [0.26 0.31 0.40], 'LineWidth', 1.0, ...
        'BackgroundColor', [0.045 0.055 0.078], ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'Color', softText, 'FontName', 'Arial', 'FontSize', 10.5, ...
        'FontWeight', 'bold', 'Interpreter', 'none');

    baseName = sprintf('Schematic_%02d_%s_lateral_views', ...
        contrastNumber, safeFileName(contrastInfo.name));

    exportgraphics(fig, fullfile(outputDir, [baseName '.png']), ...
        'Resolution', 600, 'BackgroundColor', background);
    exportgraphics(fig, fullfile(outputDir, [baseName '.pdf']), ...
        'ContentType', 'vector', 'BackgroundColor', background);
    savefig(fig, fullfile(outputDir, [baseName '.fig']));
    close(fig);

    fprintf('Saved contrast %d using cortical mesh: %s\n', ...
        contrastNumber, meshName);
end


function drawLateralBrain(ax, vertices, faces, viewingSide, resultInfo)
    hold(ax, 'on');

    baseColour = [0.58 0.62 0.68];
    vertexColours = repmat(baseColour, size(vertices,1), 1);

    if resultInfo.hasSignificantVoxels
    % Use the sign of the sensor-image x coordinate only to choose which
    % side carries the illustrative marker. Its cortical position has no
    % anatomical meaning.
        markerSide = sign(resultInfo.peakWorld(1));
        if markerSide == 0
            markerSide = 1;
        end

        vertexColours = addIllustrativeMarker( ...
            vertices, vertexColours, markerSide);
    end

    brainPatch = patch(ax, 'Faces', faces, 'Vertices', vertices, ...
        'FaceVertexCData', vertexColours, 'FaceColor', 'interp', ...
        'EdgeColor', 'none', 'FaceLighting', 'gouraud', ...
        'AmbientStrength', 0.35, 'DiffuseStrength', 0.72, ...
        'SpecularStrength', 0.18, 'SpecularExponent', 12);

    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');

    if viewingSide < 0
        view(ax, -90, 5);
    else
        view(ax, 90, 5);
    end

    camlight(ax, 'headlight');
    material(ax, 'dull');

    % Add a faint floor glow without creating another plotted data panel.
    brainPatch.FaceAlpha = 1;
end


function colours = addIllustrativeMarker(vertices, colours, markerSide)
    centre = mean(vertices, 1, 'omitnan');
    scale = max(abs(vertices - centre), [], 1);
    for coordinateNumber = 1:3
        if scale(coordinateNumber) == 0
            scale(coordinateNumber) = 1;
        end
    end
    target = [0.82 * markerSide, -0.76, 0.02];
    gold = [1.00 0.82 0.08];
    coral = [1.00 0.28 0.12];
    magenta = [0.86 0.03 0.28];

    % This marker is illustrative; it is not a reconstructed brain source.
    for vertexNumber = 1:size(vertices, 1)
        normalisedX = (vertices(vertexNumber, 1) - centre(1))/scale(1);
        normalisedY = (vertices(vertexNumber, 2) - centre(2))/scale(2);
        normalisedZ = (vertices(vertexNumber, 3) - centre(3))/scale(3);
        differenceX = (normalisedX - target(1))/0.24;
        differenceY = (normalisedY - target(2))/0.20;
        differenceZ = (normalisedZ - target(3))/0.30;
        distanceSquared = differenceX^2 + differenceY^2 + differenceZ^2;
        intensity = exp(-0.5*distanceSquared);
        if intensity < 0.10
            intensity = 0;
        end
        intensity = min(1, intensity^0.72);
        hotColour = (1-intensity)*gold + intensity*magenta;
        if intensity > 0.25 && intensity < 0.62
            hotColour = 0.45*hotColour + 0.55*coral;
        end
        mixAmount = min(1, 1.18*intensity);
        colours(vertexNumber, :) = ...
            colours(vertexNumber, :)*(1-mixAmount) + hotColour*mixAmount;
    end
end


function [vertices, faces, meshName] = loadCanonicalCortex(spmDirectory)
    preferredFiles = { ...
        fullfile(spmDirectory, 'canonical', 'cortex_8196.surf.gii'), ...
        fullfile(spmDirectory, 'canonical', 'cortex_20484.surf.gii'), ...
        fullfile(spmDirectory, 'canonical', 'cortex_5124.surf.gii')};

    meshFile = '';
    for fileNumber = 1:numel(preferredFiles)
        if isfile(preferredFiles{fileNumber})
            meshFile = preferredFiles{fileNumber};
            break;
        end
    end

    if isempty(meshFile)
        candidates = dir(fullfile(spmDirectory, '**', 'cortex_*.surf.gii'));
        if ~isempty(candidates)
            meshFile = fullfile(candidates(1).folder, candidates(1).name);
        end
    end

    if ~isempty(meshFile)
        corticalMesh = gifti(meshFile);
        vertices = double(corticalMesh.vertices);
        faces = double(corticalMesh.faces);
        [~, meshBase, meshExtension] = fileparts(meshFile);
        meshName = [meshBase meshExtension];
        return;
    end

    warning(['No canonical cortex GIfTI was found in SPM. ' ...
        'A fallback schematic surface will be used.']);
    [vertices, faces] = fallbackCorticalSurface();
    meshName = 'fallback schematic surface';
end


function [vertices, faces] = fallbackCorticalSurface()
    [x, y, z] = sphere(150);

    % Ellipsoidal hemispheric form with shallow deterministic folding.
    ripple = 1 + 0.026 .* sin(9 .* atan2(z, y)) .* ...
        cos(11 .* atan2(y, x));
    x = 66 .* x .* ripple;
    y = 92 .* y .* ripple;
    z = 70 .* z .* ripple;

    surfaceStruct = surf2patch(x, y, z, 'triangles');
    vertices = double(surfaceStruct.vertices);
    faces = double(surfaceStruct.faces);
end


function value = cellNumber(inputValue)
    if isempty(inputValue) || ~isnumeric(inputValue)
        value = NaN;
    else
        value = double(inputValue(1));
    end
end


function output = safeFileName(input)
    output = regexprep(char(input), '[^A-Za-z0-9]+', '_');
    output = regexprep(output, '^_+|_+$', '');
end
