/**
 * @description Typed response shapes of the WhatsApp Template Manager REST API. Every response has
 *              "ok": true, or "ok": false with a human-readable "error".
 *              Template "components" and "quality_score" are passed through untyped because Meta's component
 *              schema is polymorphic (for example a button "example" is an array for URL buttons and a string
 *              for COPY_CODE), which typed JSON.deserialize cannot represent.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
public with sharing class WaTemplateModels {
    public virtual class ApiResponse {
        public Boolean ok = true;
    }

    public class ErrorResponse extends ApiResponse {
        public String error;

        public ErrorResponse(String message) {
            this.ok = false;
            this.error = message;
        }
    }

    public class AccountDto {
        public String wabaId;
        public String label;

        public AccountDto(String wabaId, String label) {
            this.wabaId = wabaId;
            this.label = label;
        }
    }

    public class AccountsResponse extends ApiResponse {
        public List<AccountDto> accounts = new List<AccountDto>();
    }

    public class TemplateDto {
        public String id;
        public String name;
        public String status;
        public String category;
        public String language;
        public Object components;
        public String rejected_reason;
        public Object quality_score;
    }

    public class TemplatesResponse extends ApiResponse {
        public List<TemplateDto> templates = new List<TemplateDto>();
        public Integer count = 0;
        public Boolean truncated = false;
    }

    public class CreateResponse extends ApiResponse {
        public String id;
        public String name;
        public String language;
        public String status;
        public String category;
    }

    public class UploadResponse extends ApiResponse {
        public String header_handle;

        public UploadResponse(String headerHandle) {
            this.header_handle = headerHandle;
        }
    }
}