from django.db import migrations

GROUP = "guideline_contributor"


def create_group(apps, schema_editor):
    apps.get_model("auth", "Group").objects.get_or_create(name=GROUP)


def delete_group(apps, schema_editor):
    apps.get_model("auth", "Group").objects.filter(name=GROUP).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("guidelines", "0001_initial"),
        ("auth", "0012_alter_user_first_name_max_length"),
    ]

    operations = [migrations.RunPython(create_group, delete_group)]
