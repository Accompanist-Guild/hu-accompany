from django.apps import AppConfig


class AccountsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "User_accounts"
    # The label the first migration was applied under (and the table prefix),
    # kept so renaming the folder doesn't orphan them.
    label = "accounts"
