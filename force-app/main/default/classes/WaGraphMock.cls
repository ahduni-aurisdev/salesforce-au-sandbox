/**
 * @description HttpCalloutMock for the Meta Graph API. Routes are matched in the order added by HTTP method
 *              and a substring of the endpoint; every request is recorded so tests can assert URLs and
 *              headers (Bearer vs OAuth, file_offset). Unmatched requests get a Meta-style 404 error.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
@IsTest
public class WaGraphMock implements HttpCalloutMock {
    public final List<HttpRequest> requests = new List<HttpRequest>();
    private final List<Route> routes = new List<Route>();

    private class Route {
        String method;
        String endpointContains;
        Integer status;
        String body;
        String calloutError;
    }

    /**
     * @description Adds a response route.
     * @param method HTTP method
     * @param endpointContains substring the endpoint must contain
     * @param status HTTP status to return
     * @param body response body
     * @return this mock, for chaining
     */
    public WaGraphMock route(String method, String endpointContains, Integer status, String body) {
        Route item = new Route();
        item.method = method;
        item.endpointContains = endpointContains;
        item.status = status;
        item.body = body;
        routes.add(item);
        return this;
    }

    /**
     * @description Adds a route that throws CalloutException with the given message.
     * @param method HTTP method
     * @param endpointContains substring the endpoint must contain
     * @param message exception message
     * @return this mock, for chaining
     */
    public WaGraphMock fail(String method, String endpointContains, String message) {
        Route item = new Route();
        item.method = method;
        item.endpointContains = endpointContains;
        item.calloutError = message;
        routes.add(item);
        return this;
    }

    public HttpResponse respond(HttpRequest request) {
        requests.add(request);
        for (Route item : routes) {
            if (item.method == request.getMethod() && request.getEndpoint().contains(item.endpointContains)) {
                if (item.calloutError != null) {
                    throw new CalloutException(item.calloutError);
                }
                return build(item.status, item.body);
            }
        }
        return build(404, '{"error":{"message":"No mock route for ' + request.getMethod() + '","code":100}}');
    }

    private static HttpResponse build(Integer status, String body) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(status);
        response.setHeader('Content-Type', 'application/json');
        response.setBody(body == null ? '' : body);
        return response;
    }
}