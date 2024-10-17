PATH := ~/.solc-select/artifacts/solc-0.8.21:$(PATH)
certora-l1-farm-proxy :; PATH=${PATH} certoraRun certora/L1FarmProxy.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
certora-l2-farm-proxy :; PATH=${PATH} certoraRun certora/L2FarmProxy.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
