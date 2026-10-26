/**
 * @description Request and response contracts for the Admission Round REST API.
 * @author AU Development Team
 * @date 2026-10-16
 * @version 1.0
 * @lastModified 2026-10-16
 */
public class AdmissionRoundApiModels {
    public class RequestEnvelope {
        public List<AdmissionRoundRequest> records;
    }

    public class AdmissionRoundRequest {
        public String roundCode;
        public String roundName;
        public String admissionYear;
        public String department;
        public String program;
        public String startDate;
        public String endDate;
        public Boolean isActive;
    }

    public class ResponseEnvelope {
        public String requestId;
        public Boolean success;
        public Integer totalRecords;
        public Integer successCount;
        public Integer failureCount;
        public List<RecordResult> results = new List<RecordResult>();
    }

    public class RecordResult {
        public Integer index;
        public String roundCode;
        public Id salesforceId;
        public String action;
        public Boolean success;
        public List<String> errors = new List<String>();
    }

    @TestVisible
    private AdmissionRoundApiModels() {
    }
}