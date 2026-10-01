function outputFolder = DCM_ERP_Two_Brain_Figures(reportFile)
% Two NEW figures, separate from Results_of_DCM_ERP.m:
%   1) Six ERP-DCM source priors in sagittal/coronal/axial views.
%   2) PEB/BMA-retained DIRECTED between-group connections in the same views.
% Also exports BrainNet Viewer .node/.edge inputs and an audit of display-only
% projection distances. The saved DCMs and their original MNI positions
% are NEVER changed. Requires SPM25 and MATLAB R2020b+.
%
% Usage: out = DCM_ERP_Two_Brain_Figures;
% Or:    out = DCM_ERP_Two_Brain_Figures('E:\...\Extracted_Report_Values.mat');

    if nargin < 1 || isempty(reportFile)
        root = 'E:\Subjects44\SPM_MAT_DAT\GCM_DCM';
        candidates = dir(fullfile(root,'DCM_ERP_Report_*','Extracted_Report_Values.mat'));
        if isempty(candidates)
            error('Report MAT not found. Supply its full path to DCM_ERP_Two_Brain_Figures(reportFile).');
        end

        [~,latest] = max([candidates.datenum]);
        reportFile = fullfile(candidates(latest).folder,candidates(latest).name);
    end
    if ~isfile(reportFile)
        error('Report MAT does not exist: %s',reportFile);
    end

    if ~(exist('spm','file') == 2 && exist('gifti','file') == 2)
        error('Add your existing SPM25 installation to the MATLAB path.');
    end

    savedReport = load(reportFile,'T','NodeTable','cfg');
    if ~(isfield(savedReport,'T') && isfield(savedReport,'NodeTable') && isfield(savedReport,'cfg'))
        error('Expected T, NodeTable and cfg in Extracted_Report_Values.mat.');
    end

    connectionTable = savedReport.T;
    nodeTable = savedReport.NodeTable;
    if ~(height(nodeTable) == 6 && height(connectionTable) == 14)
        error('Expected exactly six nodes and 14 tested links.');
    end

    neededN = {'SavedName','MNI_X','MNI_Y','MNI_Z'};
    neededT = {'Source','Target','MonoMinusBi','PpRetained'};
    if ~(all(ismember(neededN,nodeTable.Properties.VariableNames)) && ...
        all(ismember(neededT,connectionTable.Properties.VariableNames)))
        error('Report table fields differ.');
    end

    names = string(nodeTable.SavedName(:));
    originalCoordinates = full(double([nodeTable.MNI_X(:),nodeTable.MNI_Y(:),nodeTable.MNI_Z(:)]));
    if ~(isequal(size(originalCoordinates),[6 3]) && all(isfinite(originalCoordinates(:))))
        error('Original MNI node coordinates are invalid.');
    end

    threshold = full(double(savedReport.cfg.Threshold));
    retainedProbability = full(double(connectionTable.PpRetained(:)));
    groupDifference = full(double(connectionTable.MonoMinusBi(:)));
    if ~(isscalar(threshold) && all(isfinite(retainedProbability)) && all(isfinite(groupDifference)))
        error('Threshold or BMA posterior values are invalid.');
    end

    selected = retainedProbability > threshold;
    if ismember('Strong',connectionTable.Properties.VariableNames)
        if ~isequal(selected,logical(full(connectionTable.Strong(:))))
            error('Saved Strong flags differ from Pp > saved threshold.');
        end

    end
    [foundSrc,source] = ismember(string(connectionTable.Source(:)),names);
    [foundDst,target] = ismember(string(connectionTable.Target(:)),names);
    if ~(all(foundSrc & foundDst) && all(source ~= target))
        error('Link names do not match the six saved sources.');
    end


    % The original ROI coordinates are source priors, which need not coincide
    % exactly with a vertex on a separately rendered cortical surface. Snap ONLY
    % the markers in these new illustrations to the nearest same-side vertex.
    % Keep the original positions in .node and the audit file.
    meshFile = fullfile(spm('Dir'),'canonical','cortex_8196.surf.gii');
    if ~isfile(meshFile)
        error('SPM canonical cortical GIfTI mesh not found: %s',meshFile);
    end

    mesh = gifti(meshFile);
    vertices = full(double(mesh.vertices));
    faces = full(double(mesh.faces));
    if ~(size(vertices,2) == 3 && size(faces,2) == 3 && ...
        all(isfinite(vertices(:))) && all(isfinite(faces(:))))
        error('Cannot use the SPM cortical mesh.');
    end

    displayXYZ = zeros(6,3);
    offsetMM = zeros(6,1);
    for nodeIndex = 1:6
        if originalCoordinates(nodeIndex,1)<0
            allowed = find(vertices(:,1) <= 0);
        else
            allowed = find(vertices(:,1) >= 0);
        end
        if isempty(allowed)
            error('Cortical mesh has no vertices on one side.');
        end

        candidateXYZ = vertices(allowed,:);
        dist2 = Inf;
        nearestVertexIndex = 1;
        for vertexIndex = 1:size(candidateXYZ, 1)
            differenceX = candidateXYZ(vertexIndex, 1) - originalCoordinates(nodeIndex, 1);
            differenceY = candidateXYZ(vertexIndex, 2) - originalCoordinates(nodeIndex, 2);
            differenceZ = candidateXYZ(vertexIndex, 3) - originalCoordinates(nodeIndex, 3);
            currentDistance = differenceX^2 + differenceY^2 + differenceZ^2;
            if currentDistance < dist2
                dist2 = currentDistance;
                nearestVertexIndex = vertexIndex;
            end
        end
        displayXYZ(nodeIndex,:) = candidateXYZ(nearestVertexIndex,:);
        offsetMM(nodeIndex) = sqrt(dist2);
    end

    parent = fileparts(reportFile);
    stamp = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
    outputFolder = fullfile(parent,['NEW_Brain_Figures_' stamp]);
    if exist(outputFolder,'dir')
        error('Output folder already exists.');
    end

    mkdir(outputFolder);
    audit = table((1:6)',names,originalCoordinates(:,1),originalCoordinates(:,2),originalCoordinates(:,3), ...
        displayXYZ(:,1),displayXYZ(:,2),displayXYZ(:,3),offsetMM, ...
        'VariableNames',{'Index','Node','OriginalMNI_X','OriginalMNI_Y','OriginalMNI_Z', ...
        'DisplayX','DisplayY','DisplayZ','DisplayShiftMM'});
    writetable(audit,fullfile(outputFolder,'Node_Display_Projection_Audit.csv'));

    [viewXY,viewAudit] = make_view_coordinates(vertices,originalCoordinates,displayXYZ,names);
    writetable(viewAudit,fullfile(outputFolder,'Node_Three_View_Display_Audit.csv'));
    leftNodes = find(originalCoordinates(:,1)<0);
    % Three orthogonal standard views. Markers and arrows are drawn on a clear
    % plane in FRONT of the mesh. Every marker is placed inside its projected
    % cortical outline, including the edge of the occipital lobe.
    draw_brain_figure(false,faces,vertices,viewXY,names,leftNodes,source,target, ...
        selected,groupDifference,threshold,max(offsetMM),fullfile(outputFolder,'01_Six_ROI_Priors_3Views'));
    draw_brain_figure(true,faces,vertices,viewXY,names,leftNodes,source,target, ...
        selected,groupDifference,threshold,max(offsetMM),fullfile(outputFolder,'02_Directed_Group_Effects_3Views'));

    % BrainNet Viewer inputs: ORIGINAL MNI priors, not the illustration vertices.
    nodePath = fullfile(outputFolder,'DCM_ERP_Original_MNI.node');
    fid = fopen(nodePath,'wt');
    if ~(fid >= 0)
        error('Cannot write %s',nodePath);
    end

    try

        for nodeIndex = 1:6
            label = regexprep(char(names(nodeIndex)),'\s+','_');
            fprintf(fid,'%.4f\t%.4f\t%.4f\t%d\t%d\t%s\n', ...
                originalCoordinates(nodeIndex,1),originalCoordinates(nodeIndex,2),originalCoordinates(nodeIndex,3),1+(originalCoordinates(nodeIndex,1)>0),3,label);
        end

    catch cleanupError
        fclose(fid);
        rethrow(cleanupError);
    end
    fclose(fid);

    allEdges = zeros(6);
    monoEdges = zeros(6);
    biEdges = zeros(6);
    for edgeIndex = 1:numel(selected)
        if ~selected(edgeIndex)
            continue;
        end
        sourceIndex = source(edgeIndex);
        targetIndex = target(edgeIndex);
        allEdges(sourceIndex,targetIndex) = 1;  % Directed: row is source, column is target.
        if groupDifference(edgeIndex)>0
            monoEdges(sourceIndex,targetIndex) = 1;
        elseif groupDifference(edgeIndex)<0
            biEdges(sourceIndex,targetIndex) = 1;
        end
    end
    writematrix(allEdges,fullfile(outputFolder,'BNV_All_Retained_Directed.edge'), ...
        'FileType','text','Delimiter','tab');
    writematrix(monoEdges,fullfile(outputFolder,'BNV_Mono_Stronger_Directed.edge'), ...
        'FileType','text','Delimiter','tab');
    writematrix(biEdges,fullfile(outputFolder,'BNV_Bi_Stronger_Directed.edge'), ...
        'FileType','text','Delimiter','tab');
    edgeAudit = connectionTable(selected,neededT);
    writetable(edgeAudit,fullfile(outputFolder,'Retained_Directed_Edges.csv'));

    fprintf('Retained directed links (Pp > %.2f): %d of 14\n',threshold,sum(selected));
    fprintf('Maximum illustration-only surface shift: %.2f mm\n',max(offsetMM));
    fprintf('New figures, BrainNet files and projection audit: %s\n',outputFolder);
    if max(offsetMM)>15
        warning(['At least one ROI prior lies >15 mm from the nearest vertex ' ...
            'of this DISPLAY mesh. Inspect Node_Display_Projection_Audit.csv; ' ...
            'do not treat projected markers as fitted source locations.']);
    end
end

function [viewCoordinates,audit] = make_view_coordinates(vertices,original,surfaceXYZ,names)
    viewCoordinates = zeros(6,2,3);
    rows = cell(18,6);
    row = 0;
    viewNames = {'Sagittal-left','Coronal-anterior','Axial-superior'};
    for viewIndex = 1:3
        meshXY = project_2d(vertices,viewIndex);
        outline = convhull(meshXY(:,1),meshXY(:,2));
        hullXY = meshXY(outline,:);
        center = mean(meshXY,1);
        for nodeIndex = 1:6
            surfaceXY = project_2d(surfaceXYZ(nodeIndex,:),viewIndex);
            viewCoordinates(nodeIndex,:,viewIndex) = inside_outline(surfaceXY,hullXY,center,12);
        end
        if viewIndex == 1
            visible = find(original(:,1)<0);
        else
            visible = 1:6;
        end
        viewCoordinates(:,:,viewIndex) = spread_nodes(viewCoordinates(:,:,viewIndex),visible,hullXY,center);
        for nodeIndex = 1:6
            surfaceXY = project_2d(surfaceXYZ(nodeIndex,:),viewIndex);
            row = row+1;
            rows(row,:) = {viewNames{viewIndex},char(names(nodeIndex)),surfaceXY(1),surfaceXY(2), ...
                viewCoordinates(nodeIndex,1,viewIndex),viewCoordinates(nodeIndex,2,viewIndex)};
        end
    end
    audit = cell2table(rows,'VariableNames', ...
        {'View','Node','SurfaceProjectedU','SurfaceProjectedV','DrawnU','DrawnV'});
    % OriginalMNI and the 3D mesh-vertex displacement are in the companion CSV.
    if ~(all(isfinite(viewCoordinates(:))) && isequal(size(original),[6 3]))
        error('View positions could not be checked.');
    end

end

function xy = spread_nodes(xy,visible,hullXY,center)
% Small deterministic display-only separation leaves room for an arrowhead.
    minimumDistance = 19;
    for iteration = 1:100
        moved = false;
        for firstIndex = 1:numel(visible)
            for secondIndex = firstIndex+1:numel(visible)
                firstNode = visible(firstIndex);
                secondNode = visible(secondIndex);
                delta = xy(secondNode,:)-xy(firstNode,:);
                distance = norm(delta);
                if distance >= minimumDistance
                    continue
                end
                if distance<1e-8
                    theta = mod((firstNode*73+secondNode*47),180)*pi/180;
                    delta = [cos(theta),sin(theta)];
                    distance = 1;
                end
                direction = delta/distance;
                step = min(2,(minimumDistance-distance)/2+.02);
                xy(firstNode,:) = inside_outline(xy(firstNode,:)-step*direction,hullXY,center,12);
                xy(secondNode,:) = inside_outline(xy(secondNode,:)+step*direction,hullXY,center,12);
                moved = true;
            end
        end
        if ~moved
            return
        end
    end
    warning('Some projected regions remain close; inspect the three-view illustration.');
end

function coordinates2D = project_2d(coordinates3D,viewIndex)
    switch viewIndex
    case 1
        coordinates2D = coordinates3D(:,[2 3]);   % sagittal: anterior-posterior vs superior
    case 2
        coordinates2D = coordinates3D(:,[1 3]);   % coronal: left-right vs superior
    case 3
        coordinates2D = coordinates3D(:,[1 2]);   % axial: left-right vs anterior-posterior
    end
end

function nodePosition = inside_outline(nodePosition,hullXY,center,margin)
% Prevent the ENTIRE marker, not just its centre, from straddling the edge.
% This is a display-only relocation. No DCM coordinates are edited.
    segmentStart = hullXY(1:end-1,:);
    segmentEnd = hullXY(2:end,:);
    segment = segmentEnd-segmentStart;
    for iteration = 1:100
        rel = nodePosition-segmentStart;
        weight = sum(rel.*segment,2)./max(sum(segment.^2,2),eps);
        weight = max(0,min(1,weight));
        nearest = segmentStart+weight.*segment;
        clearance = min(sqrt(sum((nearest-nodePosition).^2,2)));
        if inpolygon(nodePosition(1),nodePosition(2),hullXY(:,1),hullXY(:,2)) && clearance >= margin
            return
        end
        nodePosition = center+.88*(nodePosition-center);
    end
    error('A node cannot be placed inside the projected cortical outline.');
end

function xyz = front_plane(coordinates2D,viewIndex,vertices)
% Project 2D network primitives onto a plane closer to the camera than any
% mesh vertex; their arrowheads therefore cannot hide under the brain mesh.
    switch viewIndex
    case 1
        xyz = [repmat(min(vertices(:,1))-25,size(coordinates2D,1),1),coordinates2D];
    case 2
        xyz = [coordinates2D(:,1),repmat(max(vertices(:,2))+25,size(coordinates2D,1),1),coordinates2D(:,2)];
    case 3
        xyz = [coordinates2D,repmat(max(vertices(:,3))+25,size(coordinates2D,1),1)];
    end
end

function draw_brain_figure(drawEdges,faces,vertices,viewCoordinates,names,leftNodes,source,target, ...
    selected,effect,threshold,maxShift,base)
    fig = figure('Visible','off','Color','white','Position',[40 50 2100 870]);
    try

        if drawEdges
            heading = 'Directed ERP-DCM group effects: arrows point FROM source TO target';
        else
            heading = 'Six ERP-DCM source priors | three anatomical views';
        end
        annotation(fig,'textbox',[.04 .92 .92 .056],'String',heading, ...
            'FontName','Arial','FontSize',23,'FontWeight','bold', ...
            'HorizontalAlignment','center','EdgeColor','none');
        titles = {'SAGITTAL  |  left','CORONAL  |  front','AXIAL  |  top'};
        cameras = {[-1 0 0],[0 1 0],[0 0 1]};
        upVectors = {[0 0 1],[0 0 1],[0 1 0]};
        for viewIndex = 1:3
            ax = axes(fig,'Position',[.025+(viewIndex-1)*.325 .23 .30 .62]);
            hold(ax,'on');
            patch(ax,'Faces',faces,'Vertices',vertices,'FaceColor',[.72 .78 .87], ...
                'FaceAlpha',.58,'EdgeColor','none','FaceLighting','gouraud');
            nodePositions2D = viewCoordinates(:,:,viewIndex);
            if viewIndex == 1
                visibleNodes = leftNodes;
            else
                visibleNodes = 1:6;
            end
            if drawEdges
                for edgeIndex = 1:numel(selected)
                    if ~selected(edgeIndex)
                        continue;
                    end
                    sourceIndex = source(edgeIndex);
                    targetIndex = target(edgeIndex);
                    if viewIndex == 1 && (~ismember(sourceIndex,visibleNodes) || ~ismember(targetIndex,visibleNodes))
                        continue
                    end
                    if effect(edgeIndex)>0
                        color = [.90 .26 .08];
                    elseif effect(edgeIndex)<0
                        color = [.07 .39 .78];
                    else
                        color = [.38 .43 .49];
                    end
                    % Reciprocal links are curved to opposite sides of their pair.
                    pairVector = nodePositions2D(max(sourceIndex,targetIndex),:)-nodePositions2D(min(sourceIndex,targetIndex),:);
                    if norm(pairVector)<1e-6
                        warning('Skipping one visually overlapping connection in view %d.',viewIndex);
                        continue
                    end
                    normal = [-pairVector(2),pairVector(1)]/norm(pairVector);
                    reciprocal = any(selected(:) & source == targetIndex & target == sourceIndex);
                    bend = 4;
                    if reciprocal
                        bend = 11;
                        if sourceIndex>targetIndex
                            bend = -bend;
                        end
                    end
                    edgeLength = norm(nodePositions2D(targetIndex,:)-nodePositions2D(sourceIndex,:));
                    trim = min(.28,9/edgeLength);
                    curveTimes = linspace(trim,1-trim,70)';
                    curve = zeros(numel(curveTimes), 2);
                    for pointIndex = 1:numel(curveTimes)
                        curveTime = curveTimes(pointIndex);
                        straightPoint = (1-curveTime)*nodePositions2D(sourceIndex, :) + curveTime*nodePositions2D(targetIndex, :);
                        curveOffset = bend*sin(pi*curveTime)*normal;
                        curve(pointIndex, :) = straightPoint + curveOffset;
                    end
                    pathXYZ = front_plane(curve,viewIndex,vertices);
                    plot3(ax,pathXYZ(:,1),pathXYZ(:,2),pathXYZ(:,3), ...
                        'Color',color,'LineWidth',4.2);
                    tip = curve(end,:);
                    tangent = curve(end,:)-curve(end-5,:);
                    tangent = tangent/norm(tangent);
                    side = [-tangent(2),tangent(1)];
                    headLength = min(11,max(6,.22*edgeLength));
                    headWidth = .48*headLength;
                    triangle = [tip;tip-headLength*tangent+headWidth*side; ...
                        tip-headLength*tangent-headWidth*side];
                    triangleXYZ = front_plane(triangle,viewIndex,vertices);
                    patch(ax,'Faces',[1 2 3],'Vertices',triangleXYZ, ...
                        'FaceColor',color,'EdgeColor','none','FaceAlpha',1);
                end
            end
            nodesXYZ = front_plane(nodePositions2D(visibleNodes,:),viewIndex,vertices);
            scatter3(ax,nodesXYZ(:,1),nodesXYZ(:,2),nodesXYZ(:,3), ...
                400,[.98 .72 .19],'filled','MarkerEdgeColor',[.12 .18 .28], ...
                'LineWidth',1.3);
            for nodeIndex = visibleNodes(:)'
                labelXYZ = front_plane(nodePositions2D(nodeIndex,:),viewIndex,vertices);
                text(ax,labelXYZ(1),labelXYZ(2),labelXYZ(3),num2str(nodeIndex), ...
                    'FontName','Arial','FontSize',16,'FontWeight','bold', ...
                    'Color',[.08 .12 .22],'HorizontalAlignment','center', ...
                    'VerticalAlignment','middle');
            end
            axis(ax,'equal');
            axis(ax,'off');
            view(ax,cameras{viewIndex});
            camup(ax,upVectors{viewIndex});
            camproj(ax,'orthographic');
            camlight(ax,'headlight');
            title(ax,titles{viewIndex},'FontName','Arial','FontSize',18,'FontWeight','bold');
        end
        labels = strings(1,6);
        for nodeIndex = 1:6
            labels(nodeIndex) = sprintf('%d = %s',nodeIndex,char(names(nodeIndex)));
        end
        annotation(fig,'textbox',[.055 .154 .89 .057], ...
            'String',char(strjoin(labels,'       ')), ...
            'FontName','Arial','FontSize',15,'HorizontalAlignment','center', ...
            'EdgeColor','none','Interpreter','none');
        if drawEdges
            legendText = sprintf(['Arrow tail = source; arrow tip = target.  ' ...
                'Orange: monolingual > bilingual; blue: bilingual > monolingual.  ' ...
                'Only Pp > %.2f effects are shown.'],threshold);
        else
            legendText = 'Numbered dots mark the six model regions; this is not a source activation map.';
        end
        annotation(fig,'textbox',[.055 .080 .89 .054], ...
            'String',legendText,'FontName','Arial','FontSize',14, ...
            'HorizontalAlignment','center','EdgeColor','none');
        annotation(fig,'textbox',[.055 .012 .89 .056], ...
            'String',sprintf(['Dots/arrows are adjusted ONLY within each 2D brain view for clarity; ' ...
            'original MNI priors are unchanged. 3D mesh projection max %.1f mm. ' ...
            'Sagittal shows left-only; lines depict model direction, not physical tracts.'],maxShift), ...
            'FontName','Arial','FontSize',11,'HorizontalAlignment','center','EdgeColor','none');
        savefig(fig,[base '.fig']);
        exportgraphics(fig,[base '.png'],'Resolution',400,'BackgroundColor','white');
        exportgraphics(fig,[base '.pdf'],'ContentType','image','Resolution',300);

    catch cleanupError
        close(fig);
        rethrow(cleanupError);
    end
    close(fig);
end
