/** Jest stub for lightning/actions (not shipped with sfdx-lwc-jest). */
export const CloseActionScreenEvent = class CloseActionScreenEvent extends CustomEvent {
    constructor() {
        super('close');
    }
};
