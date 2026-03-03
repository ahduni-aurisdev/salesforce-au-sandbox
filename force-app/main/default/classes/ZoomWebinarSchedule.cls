global class ZoomWebinarSchedule implements Schedulable {
    
    // Implement the 'execute' method to run your logic
    global void execute(SchedulableContext sc) {
        // This is where your logic to fetch and update webinar registrants will go
        ZoomWebinarService zoomService = new ZoomWebinarService();
        zoomService.fetchAndUpdateWebinarRegistrants();
    }
}