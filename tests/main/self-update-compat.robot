*** Settings ***
Resource            ../resources/common.resource
Library             DateTime

Test Teardown       Stop Device

Test Tags           self-update


*** Test Cases ***
Update From Legacy Versions
    [Template]    Upgrade From Base Image
    ghcr.io/thin-edge/tedge-container-bundle:20241126.1855    tedge-container-bundle:20241126.1855


*** Keywords ***
Upgrade From Base Image
    [Arguments]    ${IMAGE}    ${SOFTWARE_VERSION}
    # pre-condition
    Setup Device    image=${IMAGE}
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "${SOFTWARE_VERSION}", "softwareType": "self"}    timeout=10

    ${operation}=    Cumulocity.Install Software
    ...    {"name": "tedge", "version": "ghcr.io/thin-edge/tedge-container-bundle:99.99.1", "softwareType": "self"}

    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}    timeout=120
    Device Should Have Installed Software
    ...    {"name": "tedge", "version": "tedge-container-bundle:99.99.1", "softwareType": "self"}
