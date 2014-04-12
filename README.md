# baggage.io

baggage.io is a simple and free web-to-email api.

# use case

The typical use case is sending notifications from a server that can't reach any SMTP servers but can talk to the Internet on HTTP or HTTPS.

# tutorial

For a quick overview with example emails see http://baggage.io

# api

### endpoints

* http://api.baggage.io
* https://api.baggage.io

### output

Output defaults to application/json. You can set the required format using the HTTP Accept header. For example

    curl -is -H 'Accept: application/xml' https://api.baggage.io/ping

The following are accepted:

* text/plain (actually just text/yaml)
* text/yaml
* application/json (default)
* application/yaml

### status codes

* Returns 200 on success
* Returns 400 on error
* Returns 404 for unknown requests
* Returns 500 when something really bad happens

## subscribe

__GET /subscribe/{email\_address}__

To receive emails you must subscribe an email address. Each subscription has a unique ID associated with it, and you can have as many subscriptions per email address as you like. 

When you subscribe, you will receive an email containing the tokens necessary for sending emails or managing the subscription.

    curl -is 'https://api.baggage.io/subscribe/{email_address}?expires={expires}&name={name}'

| Parameter | Description | Type | Validation | Required | Default |
|-----------|-------------|------|------------|:--------:|---------|
| email\_address | Email address you would like to subscribe | String | Any valid email address | Yes | NA |
| expires | Number of days of inactivity before the subscription expires | Integer | 1 to 365 | No | 7 |
| name | A convenient descriptive name | String | Alphanumerics plus space, - and \_. Up to 64 chars. | No | baggage.io |

Output on success:

    {"message":"subscription sent"}


## send

__GET /send/{id}__

Used to send an email to the subscribed email address.

    curl -is 'https://api.baggage.io/send/{id}?token={email_token}&subject={subject}&from={from}&body={body}'

| Parameter | Description | Type | Validation | Required | Default |
|-----------|-------------|------|------------|:--------:|---------|
| id | Unique subscription ID | String | Hex 32 chars | Yes | NA |
| token | Email token | String | Hex 64 chars | Yes | NA |
| subject | Subject of the email to send | String | Not empty | Yes | NA |
| from | From address name | String | Not empty | No | baggage.io |
| body | Body of the email to send | String | Not empty | Yes | NA |

__POST /send/{id}__

Here the body comes from the body of the request so the body parameter isn't required.

    curl -is -XPOST --data-binary @body.txt -H 'Content-Type: application/octet-stream' 'https://api.baggage.io/send/{id}?token={email_token}&subject={subject}&from={from}'

| Parameter | Description | Type | Validation | Required | Default |
|-----------|-------------|------|------------|:--------:|---------|
| id | Unique subscription ID | String | Hex 32 chars | Yes | NA |
| token | Email token | String | Hex 64 chars | Yes | NA |
| subject | Subject of the email to send | String | Not empty | Yes | NA |
| from | From address name | String | Not empty | No | baggage.io |

Output on success:

    {"message":"sent"}


## stats

__GET /stats/{id}__

Retrieve subscription statistics. This does not send an email.

    curl -is 'https://api.baggage.io/stats/{id}?token={token}'

| Parameter | Description | Type | Validation | Required | Default |
|-----------|-------------|------|------------|:--------:|---------|
| id | Unique subscription ID | String | Hex 32 chars | Yes | NA |
| token | Admin token | String | Hex 64 chars | Yes | NA |

Output on success:

    {"message":"stats","stats":{"email":"you@domain.com","name":"baggage.io","created":"2014-04-07 23:48:18 +0100","updated":"2014-04-07 23:49:36 +0100","sent_count":1,"subscriber_ip":"127.0.0.1","last_admin_ip":"127.0.0.1","last_sender_ip":"127.0.0.1","ttl":604797}}

* __email__ - subscribed email address
* __name__ - descriptive name
* __created__ - when the subscription was created
* __updated__ - when the subscription was last updated or used
* __sent\_count__ - number of messages sent
* __subscriber\_ip__ - client IP address when subscription was created
* __last\_admin\_ip__ - client IP address of the last admin request
* __last\_sender\_ip__ - client IP address of the last send request
* __ttl__ - number of seconds before subscription expires of inactivity (time to live)


## update

__GET /update/{id}__

Update subscription attributes. This does not send an email.

    curl -is 'https://api.baggage.io/update/{id}?token={token}&name={name}&expires={expires}'

| Parameter | Description | Type | Validation | Required | Default |
|-----------|-------------|------|------------|:--------:|---------|
| id | Unique subscription ID | String | Hex 32 chars | Yes | NA |
| token | Admin token | String | Hex 64 chars | Yes | NA |
| name | A convenient descriptive name | String | Alphanumerics plus space, - and \_. Up to 64 chars. | No | baggage.io |
| expires | Number of days of inactivity before the subscription expires | Integer | 1 to 365 | No | 7 |

Output on success:

    {"message":"updated"}


## rotate

__GET /rotate/{id}__

Used to change the tokens. The ID remains the same and both tokens get rotated. An email is sent with the new tokens. It can also be used to change the expiry period.

    curl -is 'https://api.baggage.io/rotate/{id}?token={token}'

| Parameter | Description | Type | Validation | Required | Default |
|-----------|-------------|------|------------|:--------:|---------|
| id | Unique subscription ID | String | Hex 32 chars | Yes | NA |
| token | Admin token | String | Hex 64 chars | Yes | NA |

Output on success:

    {"message":"rotated"}


## unsubscribe

__GET /unsubscribe/{id}__

Deletes the subscription for the given ID. If an email address has multiple subscriptions, this only affects the one for the ID provided.

    curl -is 'https://api.baggage.io/unsubscribe/{id}?token={token}

| Parameter | Description | Type | Validation | Required | Default |
|-----------|-------------|------|------------|:--------:|---------|
| id | Unique subscription ID | String | Hex 32 chars | Yes | NA |
| token | Admin token | String | Hex 64 chars | Yes | NA |

Output on success:

    {"message":"unsubscribed"}


## ping

__GET /ping__

Simple connectivity test.

    curl -is https://api.baggage.io/ping

Output on success:

    {"message":"pong"}


# contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
