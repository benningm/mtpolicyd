Feature: mtpolicyd running with a basic spamhaus RBL config
  The mtpolicyd must be able to start up with a basic Spamhaus RBL config.

  Scenario: mtpolicyd with a basic Spamhaus configuration
    Given that a mtpolicyd is running with configuration t-data/spamhaus-rbls.conf
    When the following request is executed on mtpolicyd:
    """
    sender=mtpolicyd@bofh-noc.de
    client_address=1.11.122.176
    reverse_client_name=bofh-noc.de
    helo_name=bofh-noc.de
    """
    Then mtpolicyd must respond with a action like ^reject SBL
    When the following request is executed on mtpolicyd:
    """
    sender=mtpolicyd@bofh-noc.de
    client_address=127.0.0.4
    reverse_client_name=bofh-noc.de
    helo_name=bofh-noc.de
    """
    Then mtpolicyd must respond with a action like ^reject XBL
    When the following request is executed on mtpolicyd:
    """
    sender=mtpolicyd@bofh-noc.de
    client_address=127.0.0.10
    reverse_client_name=bofh-noc.de
    helo_name=bofh-noc.de
    """
    Then mtpolicyd must respond with a action like ^reject PBL
    When the following request is executed on mtpolicyd:
    """
    sender=mtpolicyd@dbltest.com
    client_address=127.0.0.1
    reverse_client_name=bofh-noc.de
    helo_name=bofh-noc.de
    """
    Then mtpolicyd must respond with a action like ^reject DBL sender
    When the following request is executed on mtpolicyd:
    """
    sender=mtpolicyd@bofh-noc.de
    client_address=127.0.0.1
    reverse_client_name=mail.dbltest.com
    helo_name=bofh-noc.de
    """
    Then mtpolicyd must respond with a action like ^reject DBL reverse_client_name
    When the following request is executed on mtpolicyd:
    """
    sender=mtpolicyd@bofh-noc.de
    client_address=127.0.0.1
    reverse_client_name=bofh-noc.de
    helo_name=mail.dbltest.com
    """
    Then mtpolicyd must respond with a action like ^reject DBL helo_name

