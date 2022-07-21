# Example code to show how to interact with a Telegram bot using the HTTP data source of AppSync

## Deploy

* Get a bot token using [BotFather](https://core.telegram.org/bots#6-botfather)
* ```terraform init```
* ```terraform apply``` <= you'll need the token here

## Usage

* Start a chat with your bot: [link](https://advancedweb.hu/the-easiest-way-to-set-up-a-chat-with-your-telegram-bot/#using-the-telegram-bot-setup-package)
* Send a message to the chat, use the chat_id from the previous step:

```graphql
mutation MyMutation {
  sendMessage(chat_id: "<chat id>", message: "test")
}
```

## Cleanup

* ```terraform destroy```
