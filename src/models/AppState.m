classdef AppState < handle
    properties
        baseUrl string = "http://34.42.87.190:5715"
        authToken string = ""
        tokenType string = "Bearer"
        currentUser string = ""
        defaultProjectId string = ""
        lastHealth string = "Unknown"
        selectedBackend string = ""
        selectedFile string = ""
        defaultShots double = 1024
        defaultOptimization double = 1
    end
end
