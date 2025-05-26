*** Settings ***
Resource            ../resources/common.resource
Library             DateTime

Test Teardown       Stop Device


*** Test Cases ***
Supports Cumulocity Basic Auth Credentials
    Setup Device With Basic Auth Credentials

    ${operation}=    Cumulocity.Get Configuration    typename=tedge-configuration-plugin
    Cumulocity.Operation Should Be SUCCESSFUL    ${operation}
