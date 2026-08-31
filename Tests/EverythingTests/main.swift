import Foundation

let failed = runTests(
    SearchUnitTests.cases
        + PathDisplayTests.cases
        + ScanPolicyTests.cases
        + IndexRegressionTests.cases
        + ScannerSmokeTests.cases
        + EndToEndTests.cases
)
exit(failed == 0 ? 0 : 1)
