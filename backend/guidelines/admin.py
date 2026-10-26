"""Django admin registration. Inert until django.contrib.admin is added to
INSTALLED_APPS (it isn't today -- authoring happens in the app's Guides tab).
"""

from django.contrib import admin

from .models import Guideline, Rubric, Tag


class RubricInline(admin.StackedInline):
    model = Rubric
    extra = 0


@admin.register(Guideline)
class GuidelineAdmin(admin.ModelAdmin):
    list_display = ("title", "status", "visibility", "owner", "version", "updated_at")
    list_filter = ("status", "visibility", "tags")
    filter_horizontal = ("tags",)
    inlines = [RubricInline]


@admin.register(Tag)
class TagAdmin(admin.ModelAdmin):
    list_display = ("slug", "kind")
    list_filter = ("kind",)
