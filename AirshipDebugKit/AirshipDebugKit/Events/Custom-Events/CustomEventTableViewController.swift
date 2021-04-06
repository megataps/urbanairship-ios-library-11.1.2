/* Copyright Airship and Contributors */

import UIKit
import AirshipKit

class CustomEventTableViewController: UITableViewController, UITextFieldDelegate {

    @IBOutlet var cancelButton: UIBarButtonItem!
    @IBOutlet var doneButton: UIBarButtonItem!
    
    var customEvent:UACustomEvent?

    var eventName:String?
    var eventValue:String?
    var interactionID:String?
    var interactionType:String?
    var transactionID:String?

    private var orderedProperties:[(identifier:String, value:String)]?

    private var isCleared:Bool = true

    fileprivate enum Sections : Int, CaseIterable {
        case StandardEventProperties = 0
        case AddCustomEventProperties = 1
        case CustomEventProperties = 2
    }
    
    fileprivate enum StandardEventRows : Int, CaseIterable {
        case EventName = 0
        case EventValue = 1
        case InteractionID = 2
        case InteractionType = 3
        case TransactionID = 4
    }

    fileprivate enum AddCustomEventRows : Int, CaseIterable {
        case AddCustomProperty = 0
    }

    func setTableViewTheme() {
        self.tableView.backgroundColor = ThemeManager.shared.currentTheme.Background
        self.navigationController?.navigationBar.titleTextAttributes = [.foregroundColor:ThemeManager.shared.currentTheme.NavigationBarText]
        self.navigationController?.navigationBar.barTintColor = ThemeManager.shared.currentTheme.NavigationBarBackground
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setTableViewTheme()

        self.cancelButton.tintColor = ThemeManager.shared.currentTheme.WidgetTint
        self.doneButton.tintColor = ThemeManager.shared.currentTheme.WidgetTint
        
        self.doneButton.isEnabled = (customEvent != nil)

        generateOrderedProperties()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.tintColor = ThemeManager.shared.currentTheme.WidgetTint

        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(CustomEventTableViewController.dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated);

        tableView.reloadData()
    }

    func generateOrderedProperties() {
        var orderedTuples:[(identifier:String, value:String)] = []

        guard let unorderedProperties = self.customEvent?.properties else { return }

        for (identifier, value) in unorderedProperties {
            guard let stringID = identifier as? String else { continue }

            orderedTuples.append((stringID, valueToString(value)))
        }

        orderedProperties = orderedTuples
    }

    @IBAction func addEvent(_ sender: Any) {
        if (customEvent == nil) {
            displayMessage("ua_custom_event_add_error".localized())
            return
        }

        UAirship.shared().analytics.add(customEvent!)

        displayMessage("ua_custom_event_added".localized())

        clearFields()
    }

    @IBAction func cancel(_ sender: Any) {
        self.dismiss(animated:true)
    }
    
    func lazyLoadCustomEvent() {
        if (customEvent == nil) {
            customEvent = UACustomEvent(name: eventName!, value: NSDecimalNumber(string: eventValue!))
        }

        self.doneButton.isEnabled = (customEvent != nil)
    }

    func isNumeric(_ numericString: String?) -> Bool {
        guard (numericString != nil) else {
            return false
        }

        let scanner = Scanner(string: numericString!)

        scanner.locale = NSLocale.current

        return scanner.scanDecimal(nil) && scanner.isAtEnd
    }

    func displayMessage (_ messageString: String) {
        let alertController = UIAlertController(title: "Notice", message: messageString, preferredStyle: .alert)
        
        let completeAction = UIAlertAction(title: "ua_alert_ok".localized(), style: .cancel, handler:nil)
        alertController.addAction(completeAction)

        alertController.popoverPresentationController?.sourceView = self.view
        present(alertController, animated: true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        switch textField.tag {
        case StandardEventRows.EventName.rawValue:
            if textField.text != "" {
                eventName = textField.text
            } else {
                displayMessage("Event name must be non-empty")
                textField.text = nil
            }
            break
        case StandardEventRows.EventValue.rawValue:
            if textField.text != "" && isNumeric(textField.text) {
                eventValue = textField.text
            } else {
                displayMessage("Custom event value must be a non-empty numeric")
                textField.text = nil
            }
            break
        case StandardEventRows.InteractionID.rawValue:
            interactionID = textField.text
            return
        case StandardEventRows.InteractionType.rawValue:
            interactionType = textField.text
            return
        case StandardEventRows.TransactionID.rawValue:
            transactionID = textField.text
            return
        default:
            return
        }

        if (eventName != nil && eventValue != nil) {
            // Lazy load the custom event when user inputs the last required field
            lazyLoadCustomEvent()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    @objc func dismissKeyboard() {
        view.endEditing(true)
    }

    func clearFields() {
        customEvent = nil

        eventName = nil
        eventValue = nil
        interactionID = nil
        interactionType = nil
        transactionID = nil

        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        if customEvent != nil && customEvent!.properties.count > 0 {
            return Sections.allCases.count
        }

        return (Sections.allCases.count - 1)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch (section) {
        case Sections.StandardEventProperties.rawValue:
            return StandardEventRows.allCases.count
        case Sections.AddCustomEventProperties.rawValue:
            return AddCustomEventRows.allCases.count
        case Sections.CustomEventProperties.rawValue:
            if let customEvent = customEvent {
                return customEvent.properties.count
            } else {
                return 0
            }
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        switch (indexPath.section) {
        case (Sections.StandardEventProperties.rawValue):
            switch (indexPath.row) {
            case (StandardEventRows.EventName.rawValue):
                return customEventCell(indexPath: indexPath, label: "ua_custom_event_event_name_title".localized(), placeholder: "ua_required".localized(), text: eventName)
            case (StandardEventRows.EventValue.rawValue):
                return customEventCell(indexPath: indexPath, label: "ua_custom_event_event_value_title".localized(), placeholder: "ua_required".localized(), text: eventValue)
            case (StandardEventRows.InteractionID.rawValue):
                return customEventCell(indexPath: indexPath, label: "ua_custom_event_interaction_id_title".localized(), placeholder: "ua_optional".localized(), text: interactionID)
            case (StandardEventRows.InteractionType.rawValue):
                return customEventCell(indexPath: indexPath, label: "ua_custom_event_interaction_type_title".localized(), placeholder: "ua_optional".localized(), text: interactionType)
            case (StandardEventRows.TransactionID.rawValue):
                return customEventCell(indexPath: indexPath, label: "ua_custom_event_transaction_id_title".localized(), placeholder: "ua_optional".localized(), text: transactionID)
            default:
                break;
            }
        case (Sections.AddCustomEventProperties.rawValue):
            switch (indexPath.row) {
            case (AddCustomEventRows.AddCustomProperty.rawValue):
                let cell = tableView.dequeueReusableCell(withIdentifier: "customPropertyAdderCell", for: indexPath) as! CustomPropertyAdderTableViewCell
                cell.label.text = "ua_custom_event_add_custom_property_title".localized()
                cell.isUserInteractionEnabled = true
                return cell
            default:
                break;
            }
        case (Sections.CustomEventProperties.rawValue):
            let cell = tableView.dequeueReusableCell(withIdentifier: "customPropertyCell", for: indexPath) as! CustomPropertyTableViewCell
            guard self.customEvent != nil else { return cell }
            guard let orderedProperties = self.orderedProperties else { return cell }

            let propertyTuple = orderedProperties[indexPath.row]

            cell.propertyIdentifierLabel?.text = propertyTuple.identifier
            cell.propertyLabel?.text = propertyTuple.value

            return cell
        default:
            break;
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "customPropertyCell", for: indexPath)
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        super.tableView(tableView, titleForHeaderInSection: section)
        
        if section == 0 {
            return "Event Properties"
        }

        return "Add Properties"
    }
    
    func customEventCell(indexPath: IndexPath, label: String, placeholder: String, text: String?) -> CustomEventTableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "customEventCell", for: indexPath) as! CustomEventTableViewCell
        
        cell.eventPropertyLabel.text = label
        cell.textInputField.delegate = self
        cell.textInputField.placeholder = placeholder
        cell.textInputField.text = text
        cell.textInputField.tag = indexPath.row
        cell.textInputField.textColor = ThemeManager.shared.currentTheme.Background
        
        return cell
    }

    // Helper to convert property to printable form
    func valueToString(_ value:Any) -> String {
        if let numVal = value as? NSNumber, CFGetTypeID(numVal) != CFBooleanGetTypeID() {
            return String(describing:numVal)
        }

        if let boolVal = value as? Bool {
            return boolVal ? "ua_true_false_true".localized() : "ua_true_false_false".localized()
        }

        if let stringVal = value as? String {
            return stringVal
        }

        if let arrayVal = value as? [String] {
            return arrayVal.joined(separator: ", ")
        }

        return ""
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let headerView = view as? UITableViewHeaderFooterView {
            headerView.textLabel?.textColor = ThemeManager.shared.currentTheme.WidgetTint
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if (indexPath.section == Sections.AddCustomEventProperties.rawValue && indexPath.row == AddCustomEventRows.AddCustomProperty.rawValue) {
            // Ensure a custom event is ready to add properties
            if (customEvent != nil) {
                performSegue(withIdentifier: "addCustomPropertySegue", sender: self)
            } else {
                displayMessage("ua_custom_event_set_custom_property_error".localized())
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}
