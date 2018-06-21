# A case study over LDAP, Postfix and MtPolicyd
## Abstract
With MtPolicyd you can use LDAP to profile your accounts with policies. For instance, for each **account** you can set a number of maximum message rate (for single message, or message x recipient), or a size rate too.
We see how to implement these policies per account with a working example. Suitable for a large environment.

## Requisite
Many email service implementations adopt LDAP as a DB to profile user preferences, SMTP routing information and authentication. You should have an LDAP server (ldap.example.com) with email account like this:

```
dn: uid=account@example.com,[base dn]
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: mailRecipient
objectClass: inetMailUser
mailAlternateAddress: alias@example.com
mail: account@example.com
mailDeliveryOption: mailbox
uid: account@example.com
userPassword: mypassword
cn: Account name
mailUserStatus: active
sn: Account
mailHost: imapserver.example.com
```

In this example the uid is the `sasl_username` used by Postfix to authenticate and authorize the account to send mail.
You can build this authentication process using saslauthd over LDAP mechanism, for instance.

Here we don't explain how to implement authentication, other SMTP routing mechanism or email aliases over LDAP. Anyway, let suppose the above entry is a working LDAP account used for SMTP authentication.

You can imagine other policies for _client_address_ or other keys too, using different Postfix _context_. This is not the scope of this document.

Postfix, Mtpolicyd and the LDAP server could stay on different hosts. All of them can interface each other through TCP sockets. For instance you can install

* MtPolicyd on mtpolicyd.example.com
* Postfix on postfix.example.com
* Directory Server on ldap.example.com

## Configure
As you can see in [Plugin Accounting](http://search.cpan.org/~benning/Mail-MtPolicyd-1.16/lib/Mail/MtPolicyd/Plugin/Accounting.pm), we have four counters for each key. Our key will be `sasl_username`, because we want policies per account. So we first have to declare a schema for the LDAP server.

Mtpolicyd doesn't provide an official schema. Here you can find a schema useful for the result we want achieve in this case. The schema works with Red Hat/Fedora Directory Server, but with little adjustment probably can work with OpenLDAP or other Directory Servers which support custom, **unofficial OIDs**.

This unofficial schema provides the attributes for the four counters:
* mtpolicydMailMessageLimit
* mtpolicydMailRecipientLimit
* mtpolicydMailSizeLimit
* mtpolicydMailSizeRecipientLimit

These attributes comes with the objectClass
* mtpolicyd

which extend the objectclass "mailRecipient". This choice is not mandatory, you can change it if you don't like it.

Once you have extended the schema, our LDAP entry can be profiled for MtPolicyd.
For instance we can choose to limit the account "account@example.com" to send a maximum of 100 mails per time unit.
To achieve this the entry is:

```
dn: uid=account@example.com,[base dn]
mtpolicydMailMessageLimit: 100
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: mailRecipient
objectClass: inetMailUser
objectClass: mtpolicyd
mailAlternateAddress: alias@example.com
mail: account@example.com
mailDeliveryOption: mailbox
uid: account@example.com
userPassword: mypassword
cn: Account name
mailUserStatus: active
sn: Account
mailHost: imapserver.example.com
```

We could also set the `mtpolicydMailRecipientLimit` attribute and configure MtPolicyd to refuse the mails if at least one counter triggers the threshold defined in the LDAP attribute. So, here is the complete MtPolicyd virtual host:

```
vhost_by_policy_context=1
<VirtualHost 12345>
  name="accounting"

  <Plugin LdapUID>
    module="LdapUserConfig"
    basedn="[base dn]"
    # sasl_username attribute is uid.
    filter_field="sasl_username"
    filter="(&(uid=%s)(objectClass=mailRecipient)(objectclass=mtpolicyd)(mailUserStatus=active))"
    # copy these fields to current mtpolicyd session
    config_fields="mtpolicydMailMessageLimit,mtpolicydMailRecipientLimit"
  </Plugin>

  <Plugin QuotaUser>
    module = "Quota"
    time_pattern = "%Y-%m-%d"
    field = "sasl_username"
    metric = "count"
    threshold = 500
    # if this field is set it will overwrite the default threshold
    uc_threshold = "mtpolicydMailMessageLimit"
    # for MSA you may reject, for MTAs you may defer
    action = "reject you exceeded your daily message limit"
  </Plugin>

  <Plugin QuotaUserRecipient>
    module = "Quota"
    time_pattern = "%Y-%m-%d"
    field = "sasl_username"
    metric = "count_rcpt"
    threshold = 5000
    # if this field is set it will overwrite the default threshold
    uc_threshold = "mtpolicydMailRecipientLimit"
    # for MSA you may reject, for MTAs you may defer
    action = "reject you exceeded your daily mail recipient limit"
  </Plugin>

  <Plugin AcctUser>
    module = "Accounting"
    fields = "sasl_username"
    # Perform day based limit
    time_pattern = "%Y-%m-%d"
  </Plugin>

</VirtualHost>
```
To understand how it works, we strongly suggest to read the [How to Accounting Quota CookBook](https://metacpan.org/pod/release/BENNING/Mail-MtPolicyd-2.03/lib/Mail/MtPolicyd/Cookbook/HowtoAccountingQuota.pod).

In this example the rate time unit is _day_, but you can configure hours or other just setting the proper `time_pattern`.

### Postfix interface
This is very simple. The main.cf of the Postfix server can be configured with
```
smtpd_end_of_data_restrictions =
        check_policy_service {
                inet:mtpolicyd.example.com:12345,
                policy_context=accounting
        }
```

### LDAP connection
This is an example for the LDAP connection:

```
<Connection ldap>
  module = "Ldap"
  host = "ldap.example.com"
  port = 389
  timeout = 20
  binddn = "uid=mtpolicyd,ou=admins,[base dn]"
  password = "mtpolicyd"
  starttls = 0
</Connection>
```
Don't worry if connections between MtPolicyd and LDAP server die. MtPolicyd checks if the connection is alive. If the connection dies, MtPolicyd tries to renegotiate it. This behavior has tested with load balancer and LDAP server which expires idle sessions.

The user _mtpolicyd_ can be:

```
dn: uid=mtpolicyd,ou=admins,[base dn]
uid: mtpolicyd
givenName: Mail Team
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetorgperson
sn: Policyd
cn: Mail Team Policyd
userPassword: mtpolicyd
```

Remember to set a Password Policy which doesn't expire the password of the user mtpolicyd.

On [base dn], or where mail accounts stay, you can set an aci:

```
aci: (targetattr = "objectClass || mtpolicydMailSizeLimit || uid || mtpolicydM
 ailSizeRecipientLimit || mtpolicydMailMessageLimit || mailUserStatus || mtpol
 icydMailRecipientLimit") (target = "ldap:///[base dn]")
  (targetfilter = objectclass=mtpolicyd) (version 3.0;acl "Allow MtPolicyd access
 ";allow (read,compare,search)(userdn = "ldap:///uid=mtpolicyd,ou=admins,[base dn]");)
```

This aci limits what user mtpolicyd can perform over LDAP data. But you can imagine more complex situations, where an aci time-defined can enforce a policy only during a specific time interval, such as night hours or weekend.

## The complete example
* [LDAP schema](97mtpolicyd.ldif)
* [the complete mtpolicyd.conf](mtpolicyd.conf)
