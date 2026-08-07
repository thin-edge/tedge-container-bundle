*** Settings ***
Resource            ../resources/common.resource

Suite Setup         Setup Device
Suite Teardown      Stop Device


*** Test Cases ***
Cloud Connection is Online
    ${operation}=    Cumulocity.Execute Shell Command    tedge connect c8y --test
    Operation Should Be SUCCESSFUL    ${operation}

Service status
    Cumulocity.Should Have Services    name=tedge-mapper-c8y    service_type=service    status=up    timeout=90
    Cumulocity.Should Have Services    name=tedge-agent    service_type=service    status=up

Sends measurements
    ${date_from}=    Get Test Start Time
    ${operation}=    Cumulocity.Execute Shell Command    tedge mqtt pub te/device/main///m/sensor '{"m":23.5}'
    Operation Should Be SUCCESSFUL    ${operation}
    Cumulocity.Device Should Have Measurements    type=sensor    minimum=1    after=${date_from}
