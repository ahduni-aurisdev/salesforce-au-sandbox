/**
 * @description Request and response contracts for the Task Activity REST API.
 * @author AU Development Team
 * @date 2026-10-23
 * @version 1.0
 * @lastModified 2026-10-23
 */
public class TaskActivityApiModels {
    public class RequestEnvelope {
        public List<TaskRequest> records;
    }

    public class TaskRequest {
        public String recordId;
        public String subject;
        public String dueDate;
        public String comments;
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
        public String recordId;
        public String targetType;
        public Id relatedToId;
        public Id taskId;
        public String taskStatus;
        public String action;
        public Boolean success;
        public List<String> errors = new List<String>();
    }

    @TestVisible
    private TaskActivityApiModels() {
    }
}