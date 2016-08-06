Feature: vhost by policy_context
  The mtpolicyd must select the hostname by the policy_context field
  in case the vhost_by_policy_context option is set in configuration.

  Scenario: mtpolicyd must select the correct vhost (fred)
    Given that a mtpolicyd is running with configuration t-data/vhost-by-policy-context.conf
    When the following request is executed on mtpolicyd:
    """
    policy_context=fred
    """
    Then mtpolicyd must respond with a action like ^reject my name is fred
    And the mtpolicyd server must be stopped successfull

  Scenario: mtpolicyd must select the correct vhost (horst)
    Given that a mtpolicyd is running with configuration t-data/vhost-by-policy-context.conf
    When the following request is executed on mtpolicyd:
    """
    policy_context=horst
    """
    Then mtpolicyd must respond with a action like ^reject my name is horst
    And the mtpolicyd server must be stopped successfull

  Scenario: mtpolicyd must select the correct vhost (default is fred)
    Given that a mtpolicyd is running with configuration t-data/vhost-by-policy-context.conf
    When the following request is executed on mtpolicyd:
    """
    client_address=127.0.0.1
    """
    Then mtpolicyd must respond with a action like ^reject my name is fred
    And the mtpolicyd server must be stopped successfull

