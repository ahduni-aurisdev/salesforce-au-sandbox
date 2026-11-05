/** Jest stub for lightning/refresh (not shipped with sfdx-lwc-jest). */
export const RefreshEvent = class RefreshEvent extends CustomEvent {
    constructor() {
        super('lightning__refreshevent', { bubbles: true, composed: true });
    }
};
