classdef NanionBoltzmannPlotter < handle
    properties (Access = private)
        config
        logger
    end
    methods
        function obj = NanionBoltzmannPlotter(config, logger)
            obj.config = config;
            obj.logger = logger;
        end
    end
end
