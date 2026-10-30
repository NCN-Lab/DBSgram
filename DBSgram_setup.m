function DBSgram_setup()

    % Compiled standalone applications bundle all dependencies automatically
    % and prohibit modifying the path at runtime.
    if isdeployed
        return;
    end

    rootPath = fileparts(mfilename('fullpath'));
    
    % Define required folders
    requiredFolders = {'apps', 'external','utils'};
    
    % Check and warn/enforce structure
    for i = 1:length(requiredFolders)
        folderPath = fullfile(rootPath, requiredFolders{i});
        if ~exist(folderPath, 'dir')
            warning('Folder "%s" is missing. Please ensure your directory structure is correct.', requiredFolders{i});
        end
    end
    
    % Add paths
    
    addpath(fullfile(rootPath, 'apps'));
    addpath(fullfile(rootPath, 'utils'));
    
    % Ensure DBScope exists and is not an empty submodule folder
    externalPath = fullfile(rootPath, 'external');
    dbScopePath  = fullfile(externalPath, 'DBScope');
    
    isDbScopeValid = false;
    if exist(dbScopePath, 'dir') == 7
        % List directory contents and ignore system pointers ('.', '..') and hidden OS files
        dirContents = dir(dbScopePath);
        validFiles  = dirContents(~ismember({dirContents.name}, {'.', '..', '.DS_Store', 'Thumbs.db'}));
        
        if ~isempty(validFiles)
            isDbScopeValid = true;
        end
    end
    
    if isDbScopeValid
        % Filter out any hidden .git directories before adding to path
        rawPaths = strsplit(genpath(dbScopePath), pathsep);
        cleanPaths = rawPaths(~contains(rawPaths, [filesep '.git']) & ~cellfun(@isempty, rawPaths));
        addpath(strjoin(cleanPaths, pathsep));
        fprintf('DBSgram setup complete. DBScope integrated.\n');
    else
        % Format a clinician-friendly warning dialog
        warnTitle = 'Missing Dependency: DBScope';
        warnMsg = sprintf([ ...
            'The "external/DBScope" folder is missing or empty.\n\n' ...
            'This usually happens when downloading the DBSgram Toolbox as a .zip file from GitHub.\n\n' ...
            'To fix this manually:\n' ...
            '1. Go to: https://github.com/NCN-Lab/DBScope\n' ...
            '2. Click the green "<> Code" button and select "Download ZIP".\n' ...
            '3. Unzip the downloaded file.\n' ...
            '4. Rename the unzipped folder to "DBScope" (if named "DBScope-main") and place it inside:\n' ...
            '   %s\n\n' ...
            '5. Re-run DBSgram_setup().'], externalPath);
        
        % Launch blocking warning dialog
        uiwait(warndlg(warnMsg, warnTitle, 'modal'));
        
        % Also print clickable link in the Command Window for convenience
        fprintf(2, '\n[DBSgram Setup Incomplete] DBScope is missing or empty.\n');
        fprintf('👉 Click here to download DBScope: <a href="matlab:web(''https://github.com/NCN-Lab/DBScope'',''-browser'')">https://github.com/NCN-Lab/DBScope</a>\n\n');
    end
end