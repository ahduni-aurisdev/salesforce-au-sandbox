const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    moduleNameMapper: {
        ...(jestConfig.moduleNameMapper || {}),
        '^lightning/actions$': '<rootDir>/force-app/test/jest-mocks/lightning/actions',
        '^lightning/refresh$': '<rootDir>/force-app/test/jest-mocks/lightning/refresh',
        '^lightning/modal$': '<rootDir>/force-app/test/jest-mocks/lightning/modal'
    },
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver']
};
