/**
 * @description Tests for FeatureFlagService.
 * @author AU Development Team
 * @date 2026-11-02
 * @version 1.0
 * @lastModified 2026-11-02
 */
@IsTest
private class FeatureFlagServiceTest {
    private static final String UNKNOWN_FLAG = 'Flag_That_Does_Not_Exist_X1';

    @IsTest
    static void blankNameIsDisabled() {
        System.assertEquals(false, FeatureFlagService.isEnabled(null), 'A null flag name must be treated as disabled');
        System.assertEquals(false, FeatureFlagService.isEnabled(' '), 'A blank flag name must be treated as disabled');
    }

    @IsTest
    static void missingFlagIsDisabled() {
        System.assertEquals(false, FeatureFlagService.isEnabled(UNKNOWN_FLAG), 'A flag with no record must be treated as disabled');
    }

    @IsTest
    static void testOverrideWins() {
        FeatureFlagService.testOverrides.put(UNKNOWN_FLAG, true);
        System.assertEquals(true, FeatureFlagService.isEnabled(UNKNOWN_FLAG), 'A test override of true must enable the flag');
        FeatureFlagService.testOverrides.put(UNKNOWN_FLAG, false);
        System.assertEquals(false, FeatureFlagService.isEnabled(UNKNOWN_FLAG), 'A test override of false must disable the flag');
    }
}