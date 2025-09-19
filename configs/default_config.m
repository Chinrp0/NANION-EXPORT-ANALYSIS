%% ========================================================================
%% FILE: configs/default_config.json
%% DEFAULT CONFIGURATION FILE  
%% ========================================================================
% {
%   "analysis": {
%     "numDataPoints": 23,
%     "nernstPotential": 68
%   },
%   "filters": {
%     "maxSeriesResistance": 50,
%     "maxSealResistance": 50,
%     "maxCapacitance": 250
%   },
%   "boltzmann": {
%     "corrThreshold": 0.9,
%     "slopeLimits": [-100, 0],
%     "activationVmidMax": 0,
%     "inactivationVmidRange": [-95, -30]
%   },
%   "plotting": {
%     "figureSize": [1920, 1080],
%     "dpi": 300,
%     "rowsPerFigure": 3,
%     "colsPerFigure": 4,
%     "markerSize": 8,
%     "lineWidth": 2,
%     "fontSizeTitle": 12,
%     "fontSizeAxis": 10
%   },
%   "processing": {
%     "useParallel": true,
%     "maxWorkers": 8,
%     "memoryCleanupInterval": 3,
%     "timeoutMinutes": 30
%   },
%   "io": {
%     "readMethod": "readcell",
%     "enableFallbacks": false,
%     "maxFileSizeMB": 100,
%     "encoding": "UTF-8"
%   },
%   "protocols": {
%     "activation": {
%       "columnPattern": 6,
%       "seriesResCol": [6, 12, 18],
%       "sealResCol": [7, 13, 19],
%       "capacitanceCol": [8, 14, 20],
%       "peakCurrentCol": [9, 15, 21],
%       "markerKeywords": ["Peak"]
%     },
%     "inactivation": {
%       "columnPattern": 7,
%       "seriesResCol": [6, 13, 20],
%       "sealResCol": [7, 14, 21],
%       "capacitanceCol": [8, 15, 22],
%       "inactDataCol": [9, 16, 23],
%       "actDataCol": [10, 17, 24],
%       "markerKeywords": ["Inact", "Act"]
%     }
%   }
% }
