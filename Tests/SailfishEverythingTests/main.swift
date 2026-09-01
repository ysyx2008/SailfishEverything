import Foundation
import SailfishEverythingCore

L10n.language = .english

let failed = runTests(
    SearchUnitTests.cases
        + PathDisplayTests.cases
        + L10nTests.cases
        + ScanPolicyTests.cases
        + IndexSettingsTests.cases
        + IndexRegressionTests.cases
        + ScannerSmokeTests.cases
        + QueryTests.cases
        + EndToEndTests.cases
        + ProductFlowTests.cases
        + WatchFlowTests.cases
        + AppLaunchTests.cases
        + ShipFlowTests.cases
)
exit(failed == 0 ? 0 : 1)
