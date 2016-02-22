//
//  DiagramViewController.swift
//  JIRA Commander
//
//  Created by Tim Ordenewitz on 08.02.16.
//  Copyright © 2016 Tim Ordenewitz. All rights reserved.
//

import UIKit
import Charts
import Alamofire
import Foundation

class DiagramViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    
    var authBase64 :String = ""
    var serverAdress :String = ""
    var projects = Set<Project>()
    var sprints = Set<Sprint>()
    
    let storyPointKey = "customfield_10002"
    let sprintInfoField = "customfield_10005"
    var issuesArray = [Issue]()
    var resolvedIssues = [Issue]()
    
    let searchQuery="sprint%20in%20openSprints()%20AND%20project%20in%20projectsWhereUserHasRole(Developers)"
    let maxResultsParameters = "&maxResults=5000"
    
    var projectTitles :[String] = []
    var touchArray = [CGFloat]()
    var index = 0
    let zoomThresehold :CGFloat = 0.95

    
    @IBOutlet weak var lineChartView: LineChartView!
    @IBOutlet weak var pickerViewOutlet: UIPickerView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadProjects()
        
        let deepPressGestureRecognizer = DeepPressGestureRecognizer(target: self, action: "deepPressHandler:", threshold: 0.8)
        lineChartView.addGestureRecognizer(deepPressGestureRecognizer)


        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setChart(dataPoints: [String], values: [Double], sprintLength : Int) {
        lineChartView.noDataText = "You need to provide data for the chart."
        var dataEntries: [ChartDataEntry] = []
        var dataEntriesBurndownMean: [ChartDataEntry] = []

        for i in 0..<dataPoints.count {
            let dataEntry = ChartDataEntry(value: values[i], xIndex: i)
            dataEntries.append(dataEntry)
        }
        let burndownMeanValues = buildBurndownMeanLine(values[0], nrOfDataPoints: dataPoints.count, sprintLength : sprintLength)


        for i in 0..<dataPoints.count {
            let dataEntry = ChartDataEntry(value: burndownMeanValues[i], xIndex: i)
            dataEntriesBurndownMean.append(dataEntry)
        }

        let lineChartDataSet = LineChartDataSet(yVals: dataEntries, label: "Story Points Remaining")
        let lineChartDataSet2 = LineChartDataSet(yVals: dataEntriesBurndownMean, label: "Guidline")
        lineChartDataSet2.axisDependency = .Left // Line will correlate with left axis values
        lineChartDataSet2.setColor(UIColor.greenColor().colorWithAlphaComponent(0.5))
        lineChartDataSet2.setCircleColor(UIColor.greenColor())
        lineChartDataSet2.lineWidth = 2.0
        lineChartDataSet2.circleRadius = 0.0
        lineChartDataSet2.fillAlpha = 65 / 255.0
        lineChartDataSet2.fillColor = UIColor.greenColor()
        lineChartDataSet2.highlightColor = UIColor.whiteColor()
        lineChartDataSet2.drawCircleHoleEnabled = true
        lineChartDataSet2.valueColors = [UIColor.whiteColor()]
        
        var dataSets : [LineChartDataSet] = [LineChartDataSet]()
        dataSets.append(lineChartDataSet)
        dataSets.append(lineChartDataSet2)
        
        
        let lineChartData = LineChartData(xVals: dataPoints, dataSets: dataSets)
        lineChartView.animate(xAxisDuration: 1.0, yAxisDuration: 1.0)
        lineChartView.xAxis.labelPosition = .Bottom
        lineChartView.data = lineChartData
    }
    
    override func viewWillAppear(animated: Bool) {
        self.navigationController?.setNavigationBarHidden(false, animated: false)
    }
    
    func loadProjects() {
        Alamofire.request(.GET, serverAdress + "/rest/api/latest/search?jql=" + searchQuery + maxResultsParameters)
            .responseJSON { response in
                if let JSON = response.result.value {
                    if let issues = JSON["issues"] {
                        //All Issues Reported by User
                        for var index = 0; index < issues!.count; ++index {
                            var tmpProject : Project
                            if let fields = issues![index]["fields"] {
                                if let projectArray = fields!["project"] {
                                    tmpProject = Project(title: projectArray!["name"] as! String, key: projectArray!["key"] as! String, sprints: nil)
                                    self.projects.insert(tmpProject)
                                    if let sprintInfo = fields![self.sprintInfoField] {
                                        for var index = 0; index < sprintInfo!.count; ++index {
                                            var myTempStrArray = sprintInfo![index].componentsSeparatedByString(",")
                                            if (self.checkSprintObjectForNullValues(myTempStrArray)) {
                                                let sprintName = myTempStrArray[3].componentsSeparatedByString("=")[1]
                                                let sprintStartDate = self.getDateFromObject(myTempStrArray[4].componentsSeparatedByString("=")[1])
                                                let sprintEndDate = self.getDateFromObject(myTempStrArray[5].componentsSeparatedByString("=")[1])
                                                self.sprints.insert(Sprint(name: sprintName, startDate: sprintStartDate, endDate: sprintEndDate, maxStoryPoints: 0, project: tmpProject))

                                            }
                                        }
                                    }
                                }
                            }
                        }
                        for var index = 0; index < issues!.count; ++index{
                            if let fields = issues![index]["fields"] {
                                if let projectArray = fields!["project"] {
                                    if let storyPointsJSON = fields![self.storyPointKey] {
                                        if (!(storyPointsJSON is NSNull)) {
                                            if let sprintInfo = fields![self.sprintInfoField] {
                                                for var index = 0; index < sprintInfo!.count; ++index {
                                                    var myTempStrArray = sprintInfo![index].componentsSeparatedByString(",")
                                                    let sprintName = myTempStrArray[3].componentsSeparatedByString("=")[1]
                                                    for sprintObject in self.sprints {
                                                        if (sprintObject.name == sprintName && sprintObject.project.key == (projectArray!["key"] as! String)) {
                                                            if let resolutionDateJSON = fields!["resolutiondate"] {
                                                                if (!(resolutionDateJSON is NSNull)) {
                                                                    let date = self.getDateFromObject(resolutionDateJSON! as! String)
                                                                    self.resolvedIssues.append(Issue(date: date, numberOfStorypoints: storyPointsJSON!.integerValue!, project: self.getProjectByName(projectArray!["name"] as! String)!, sprintName: sprintName))

                                                                } else {
                                                                    self.issuesArray.append(Issue(numberOfStorypoints: storyPointsJSON!.integerValue!, project: self.getProjectByName(projectArray!["name"] as! String)!, sprintName: sprintName))
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                }
                            }
                        }
                        self.computeMaxStorypointForSprint()
                        self.createProjectsArray()
                        self.pickerViewOutlet.reloadAllComponents()
                        self.buildDiagramDataValues(self.resolvedIssues, project: (self.projects.first)!)
                    }
                }
        }
    }
    
    func buildBurndownMeanLine(maxSP : Double, nrOfDataPoints : Int, sprintLength : Int) -> [Double]{
        var ret : [Double] = []
        let storyPointsPerDay = maxSP/Double(sprintLength)
        for var i = 0; i < nrOfDataPoints; ++i {
            ret.append(maxSP - Double(i) * storyPointsPerDay)
        }
        return ret
    }
    
    func checkSprintObjectForNullValues(myTempStrArray : [String]) -> Bool {
        var ret = true
        
        if (myTempStrArray[4].componentsSeparatedByString("=")[1] == "<null>" || myTempStrArray[5].componentsSeparatedByString("=")[1] == "<null>" ) {
            ret = false
        }
        return ret
    }
    

    
    func computeMaxStorypointForSprint() {
        for issueObject in issuesArray {
            for sprintObject in sprints {
                if (sprintObject.name == issueObject.sprintName  && sprintObject.project.key == issueObject.project.key) {
                    var tmpSprint = sprintObject
                    sprints.remove(sprintObject)
                    tmpSprint.maxStoryPoints = tmpSprint.maxStoryPoints! + issueObject.numberOfStorypoints
                    sprints.insert(tmpSprint)
                }
            }
        }

        for issueObject in resolvedIssues {
            for sprintObject in sprints {
                if (sprintObject.name == issueObject.sprintName  && sprintObject.project.key == issueObject.project.key) {
                    var tmpSprint = sprintObject
                    sprints.remove(sprintObject)
                    tmpSprint.maxStoryPoints = tmpSprint.maxStoryPoints! + issueObject.numberOfStorypoints
                    sprints.insert(tmpSprint)
                }
            }
        }
    }
    
    func getDateFromObject(dateObject : String) -> NSDate {
        var myStringArr = dateObject.componentsSeparatedByString("T")
        let dateFormatter = NSDateFormatter()
        dateFormatter.timeZone =  NSTimeZone(name: "UTC")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.dateFromString(myStringArr[0])!
    }
    
    func createProjectsArray() {
        for project in projects {
            var tmpProject = project
            projects.remove(project)
            for sprint in sprints {
                if (sprint.project == project) {
                    tmpProject.sprints?.append(sprint)
                }
            }
            projects.insert(tmpProject)
            projectTitles.append(project.title)
        }
    }
    
    func getProjectByName(name :String) -> Project? {
        for project in self.projects {
            if(project.title == name) {
                return project
            }
        }
        return nil
    }
    
    func buildDiagramDataValues(resolvedIssues : [Issue], project : Project) {
        let filteredResolvedIssues = filterIssuesByProject(resolvedIssues, project: project.title)
        let orderedResolvedIssues = orderByDate(filteredResolvedIssues)
        let burndownDates = getDatesInSprintTillToday(project)
        let nrOfDatesInSprint = getDatesInSprintTillEnd(project).count
        let xAxisDataSet = buildXAxisDataSet(burndownDates)
        let valueDataSet = buildValueDataSet(orderedResolvedIssues, burndownDates: burndownDates, project: project)
        setChart(xAxisDataSet, values: valueDataSet, sprintLength: nrOfDatesInSprint)
    }

    func buildXAxisDataSet(burndownDates : [burndownDate]) -> [String] {
        var tmpArray :[String] = []
        tmpArray.append("START")
        for date in burndownDates {
            tmpArray.append((date.date?.dateStringWithFormat("yyyy-MM-dd"))!)
        }
        return tmpArray
    }

    func buildValueDataSet(orderedResolvedIssues : [Issue], burndownDates: [burndownDate], project : Project) -> [Double] {
        var tmpDoubleArray : [Double] = []
        var tmpMaxStoryPoints = 0.0
        
        for sprintObject in sprints {
            if (sprintObject.project.key == project.key) {
                tmpMaxStoryPoints = Double(sprintObject.maxStoryPoints!)
            }
        }
        
        tmpDoubleArray.append(tmpMaxStoryPoints)
        
        for date in burndownDates {
            var tmpStoryPoints = 0
            for resolvedIssue in orderedResolvedIssues {
                if(date.date!.equalToDate(resolvedIssue.date!)) {
                    tmpStoryPoints = tmpStoryPoints + resolvedIssue.numberOfStorypoints
                }
            }
            if (tmpDoubleArray.count == 0) {
                tmpDoubleArray.append(tmpMaxStoryPoints - Double(tmpStoryPoints))
            } else {
                tmpDoubleArray.append(tmpDoubleArray[tmpDoubleArray.count - 1] - Double(tmpStoryPoints))
            }
        }
        return tmpDoubleArray
    }
    
    func getDatesInSprintTillToday(project : Project) ->[burndownDate]{
        var ret : [burndownDate] = []
        for sprint in sprints {
            if(sprint.project == project) {
                for var date = sprint.startDate; date.isLessThanDate(NSDate()); date = date.addDays(1) {
                    if(!date.inWeekend) {
                        ret.append(burndownDate(date: date, numberOfStorypoints: 0))
                    }
                }
            }
        }
        return ret
    }
    
    func getDatesInSprintTillEnd(project : Project) ->[burndownDate]{
        var ret : [burndownDate] = []
        for sprint in sprints {
            if(sprint.project == project) {
                for var date = sprint.startDate; date.isLessThanDate(sprint.endDate); date = date.addDays(1) {
                    if(!date.inWeekend) {
                        ret.append(burndownDate(date: date, numberOfStorypoints: 0))
                    }
                }
            }
        }
        return ret
    }
    
    func orderByDate(resolvedIssues : [Issue]) -> [Issue] {
        let tmpArray = resolvedIssues.sort { (res1, res2) -> Bool in
            return res2.date!.isGreaterThanDate(res1.date!)
        }
        return tmpArray
    }
    
    func uniq<S : SequenceType, T : Hashable where S.Generator.Element == T>(source: S) -> [T] {
        var buffer = [T]()
        var added = Set<T>()
        for elem in source {
            if !added.contains(elem) {
                buffer.append(elem)
                added.insert(elem)
            }
        }
        return buffer
    }

    func filterIssuesByProject(resolvedIssues :[Issue], project: String) -> [Issue]{
        var tmpArray: [Issue] = []
        for var index = 0; index < resolvedIssues.count; ++index {
            if(project == resolvedIssues[index].project.title) {
                tmpArray.append(resolvedIssues[index])
            }
        }
        return tmpArray
    }
    
    //Picker View Stuff
    func pickerView(pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return projects.count
    }
    
    func pickerView(pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        for project in projects {
            if (project.title == projectTitles[row]) {
                buildDiagramDataValues(resolvedIssues, project: project)
            }
        }
    }
    
    func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return projectTitles[row]
    }
    
    func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func deepPressHandler(recognizer: DeepPressGestureRecognizer) {
        
        if(recognizer.state == .Began) {
        }
        
        if(recognizer.state == .Changed) {
            touchArray.insert(recognizer.force, atIndex: index)
            guard touchArray.count > 7 else {
                lineChartView.zoom((zoomThresehold + recognizer.force / 10), scaleY: (zoomThresehold + recognizer.force / 10) , x: recognizer.xTouch, y: recognizer.yTouch)
                index++
                return
            }
            let point1 = lineChartView.getEntryByTouchPoint(recognizer.point!)
            let point2 = lineChartView.getPosition(point1, axis: ChartYAxis.AxisDependency.Left)
            lineChartView.zoom((zoomThresehold + touchArray[index - 7] / 10), scaleY: (zoomThresehold + touchArray[index - 7] / 10) , x: point2.x, y: (lineChartView.getYAxisMaxWidth(ChartYAxis.AxisDependency.Left)/2) + 100)
            index++
        }
        
        if(recognizer.state == .Ended) {
        }
    }
}

struct Project {
    var title : String
    var key : String
    var sprints : [Sprint]?
}

struct burndownDate {
    var date : NSDate?
    var numberOfStorypoints : Int
}

struct Issue {
    var date : NSDate?
    var numberOfStorypoints : Int
    var project : Project
    var sprintName : String
    
    init(numberOfStorypoints: Int, project : Project, sprintName : String) {
        self.numberOfStorypoints = numberOfStorypoints
        self.project = project
        self.sprintName = sprintName
    }
    
    init(date : NSDate, numberOfStorypoints: Int, project : Project, sprintName : String) {
        self.date = date
        self.numberOfStorypoints = numberOfStorypoints
        self.project = project
        self.sprintName = sprintName
    }
}

struct Sprint {
    var name : String
    var startDate : NSDate
    var endDate : NSDate
    var maxStoryPoints : Int?
    var project : Project

}
// MARK: Hashable
extension Sprint: Hashable {
    var hashValue: Int {
        return name.hashValue ^ project.hashValue
    }
}

// MARK: Equatable
func ==(lhs: Sprint, rhs: Sprint) -> Bool {
    return lhs.name == rhs.name && lhs.project == rhs.project
}

// MARK: Hashable
extension Project: Hashable {
    var hashValue: Int {
        return title.hashValue ^ key.hashValue
    }
}

// MARK: Equatable
func ==(lhs: Project, rhs: Project) -> Bool {
    return lhs.title == rhs.title && lhs.key == rhs.key
}

extension NSDate {
    func isGreaterThanDate(dateToCompare: NSDate) -> Bool {
        //Declare Variables
        var isGreater = false
        
        //Compare Values
        if self.compare(dateToCompare) == NSComparisonResult.OrderedDescending {
            isGreater = true
        }
        
        //Return Result
        return isGreater
    }
    
    func isLessThanDate(dateToCompare: NSDate) -> Bool {
        //Declare Variables
        var isLess = false
        
        //Compare Values
        if self.compare(dateToCompare) == NSComparisonResult.OrderedAscending {
            isLess = true
        }
        
        //Return Result
        return isLess
    }
    
    func equalToDate(dateToCompare: NSDate) -> Bool {
        //Declare Variables
        var isEqualTo = false
        
        //Compare Values
        if self.compare(dateToCompare) == NSComparisonResult.OrderedSame {
            isEqualTo = true
        }
        
        //Return Result
        return isEqualTo
    }
    
    func addDays(daysToAdd: Int) -> NSDate {
        let secondsInDays: NSTimeInterval = Double(daysToAdd) * 60 * 60 * 24
        let dateWithDaysAdded: NSDate = self.dateByAddingTimeInterval(secondsInDays)
        
        //Return Result
        return dateWithDaysAdded
    }
    
    func addHours(hoursToAdd: Int) -> NSDate {
        let secondsInHours: NSTimeInterval = Double(hoursToAdd) * 60 * 60
        let dateWithHoursAdded: NSDate = self.dateByAddingTimeInterval(secondsInHours)
        
        //Return Result
        return dateWithHoursAdded
    }
    
    func dateStringWithFormat(format: String) -> String {
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = format
        return dateFormatter.stringFromDate(self)
    }
    
    var inWeekend: Bool {
        let calendar = NSCalendar.currentCalendar()
        return calendar.isDateInWeekend(self)
    }
}