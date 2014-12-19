Feature: the mtpolicyd must be able to start
  The mtpolicyd must be able to start up with a basic config file.

  Scenario: mtpolicyd startup with minimal configuration
    Given that a mtpolicyd is running with configuration t-data/minimal.conf
    When the following request is executed on mtpolicyd:
    """
    client_address=84.204.103.98
    """
    Then mtpolicyd must respond with a action like ^reject test
