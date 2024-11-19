*** Settings ***
Resource        ../resources/common.resource
Library         DateTime
Library         Cumulocity
Library         DeviceLibrary

Suite Setup     Set Main Device

Test Tags       self-update


*** Test Cases ***
Trigger self update via local command
    ${cmd_id}=    DateTime.Get Current Date    time_zone=UTC    result_format=epoch
    ${topic}=    Set Variable    te/device/main///cmd/self_update/local-${cmd_id}
    ${operation}=    Cumulocity.Execute Shell Command
    ...    tedge mqtt pub -r ${topic} '{"status":"init","image":"tedge-container-bundle-tedge"}'
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}

    # TODO: Check the status of the operation
    ${operation}=    Cumulocity.Execute Shell Command
    ...    cat /data/tedge/logs/agent/workflow-self_update-local-*.log ${topic} | tail -n50 || true

    ${operation}=    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}

    ${operation}=    Cumulocity.Execute Shell Command
    ...    echo Checking MQTT messages; timeout 60 tedge mqtt sub ${topic} || true
    ${operation}=    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}
    Should Contain    ${operation["c8y_Command"]["result"]}    "status":"successful"
    [Teardown]    Clear Local Operation    ${topic}

Self update should only update if there is a new image
    ${operation}=    Cumulocity.Install Software
    ...    {"name": "tedge", "version": "tedge-container-bundle-tedge", "softwareType": "self"}
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}
    # TODO: Robotframework does not provide an easy way to provide the datetime with timezone (which is required by c8y-api)
    # Cumulocity.Device Should Have Event/s    type=tedge_self_update    after=${date}    minimum=0    maximum=0

Self update using software update operation
    # pre-condition
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "tedge-container-bundle-tedge", "softwareType": "self"}    timeout=10

    ${operation}=    Cumulocity.Install Software
    ...    {"name": "tedge", "version": "tedge-container-bundle-tedge-next", "softwareType": "self"}

    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}    timeout=120
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "tedge-container-bundle-tedge-next", "softwareType": "self"}
    [Teardown]    Collect Log Files


*** Keywords ***
Clear Local Operation
    [Arguments]    ${topic}
    ${operation}=    Cumulocity.Execute Shell Command    tedge mqtt pub -r ${topic} ''
    ${operation}=    Cumulocity.Operation Should Be DONE    ${operation}

Collect Log Files
    ${operation}=    Cumulocity.Execute Shell Command
    ...    find /data/tedge/logs/agent/ -type f -name "workflow-software_update*.log" -exec ls -t1 {} + | head -1 | xargs tail -c 15000
    ${operation}=    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}
    Log    ${operation["c8y_Command"]["result"]}
