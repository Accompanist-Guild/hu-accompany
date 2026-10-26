"""Verify (or un-verify) a guideline contributor.

    python manage.py guideline_contributor add someone@example.com
    python manage.py guideline_contributor remove someone@example.com
    python manage.py guideline_contributor list
"""

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.core.management.base import BaseCommand, CommandError

from guidelines.permissions import CONTRIBUTOR_GROUP


class Command(BaseCommand):
    help = "Add, remove or list verified guideline contributors."

    def add_arguments(self, parser):
        parser.add_argument("action", choices=["add", "remove", "list"])
        parser.add_argument("email", nargs="?")

    def handle(self, *args, action, email=None, **options):
        group, _ = Group.objects.get_or_create(name=CONTRIBUTOR_GROUP)
        if action == "list":
            for user in group.user_set.order_by("email"):
                self.stdout.write(user.email)
            return
        if not email:
            raise CommandError("An email is required.")
        user = get_user_model().objects.filter(email__iexact=email.strip()).first()
        if user is None:
            raise CommandError(f"No account with email {email}.")
        if action == "add":
            group.user_set.add(user)
            self.stdout.write(self.style.SUCCESS(f"{user.email} is now a verified contributor."))
        else:
            group.user_set.remove(user)
            self.stdout.write(self.style.SUCCESS(f"{user.email} is no longer a contributor."))
