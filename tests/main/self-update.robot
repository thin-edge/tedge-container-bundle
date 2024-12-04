*** Settings ***
Resource            ../resources/common.resource
Library             DateTime

Test Setup          Setup Device
Test Teardown       Stop Device

Test Tags           self-update


*** Test Cases ***
Trigger self update via local command
    [Tags]    self-update    test:retry(2)
    # WORKAROUND: Test fails sporadically due to the tedge-agent occasionally processing the command twice
    # Though it may have been fixed since 1.3.1
    ${cmd_id}=    DateTime.Get Current Date    time_zone=UTC    result_format=epoch
    ${topic}=    Set Variable    te/device/main///cmd/self_update/local-${cmd_id}
    ${operation}=    Cumulocity.Execute Shell Command
    ...    tedge mqtt pub -r -q 2 ${topic} '{"status":"init","image":"ghcr.io/thin-edge/tedge-container-bundle:99.99.1","containerName":"tedge"}'
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}

    ${operation}=    Cumulocity.Execute Shell Command
    ...    echo Checking MQTT messages; timeout 2 tedge mqtt sub ${topic} || true
    ${operation}=    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}
    Should Contain    ${operation["c8y_Command"]["result"]}    "status":"successful"

Self update should only update if there is a new image
    ${operation}=    Cumulocity.Install Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.1", "softwareType": "container"}
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}
    # robocop: disable=todo-in-comment
    # TODO: Robotframework does not provide an easy way to provide the datetime with timezone (which is required by c8y-api)
    # Cumulocity.Device Should Have Event/s    type=tedge_self_update    after=${date}    minimum=0    maximum=0

Self update using software update operation
    # pre-condition
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.1", "softwareType": "container"}
    ...    timeout=10

    ${operation}=    Cumulocity.Install Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.2", "softwareType": "container"}

    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}    timeout=120
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.2", "softwareType": "container"}

    # updater container should be removed (logs are already collected as part of the workflow)
    Cumulocity.Should Have Services    service_type=container    name=tedge-updater    min_count=0    max_count=0

Rollback when trying to install a non-tedge based image
    # pre-condition
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.1", "softwareType": "container"}
    ...    timeout=10

    ${operation}=    Cumulocity.Install Software
    ...    {"name": "tedge", "version": "docker.io/library/alpine:latest", "softwareType": "container"}

    Cumulocity.Operation Should Be FAILED    ${operation}    timeout=120
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.1", "softwareType": "container"}

Self update using software update operation using Container type
    # pre-condition
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.1", "softwareType": "container"}
    ...    timeout=10
    Device Should Not Have Installed Software
    ...    {"name": "app20", "version": "docker.io/library/nginx:1-alpine", "softwareType": "container"}    timeout=10

    ${operation}=    Cumulocity.Install Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.2", "softwareType": "container"}
    ...    {"name": "app20", "version": "docker.io/library/nginx:1-alpine", "softwareType": "container"}

    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}    timeout=180
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.2", "softwareType": "container"}
    ...    {"name": "app20", "version": "docker.io/library/nginx:1-alpine", "softwareType": "container"}
