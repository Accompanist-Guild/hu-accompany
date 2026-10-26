from django.urls import path

from . import views

urlpatterns = [
    path("api/guidelines", views.guidelines_view),
    path("api/guidelines/tags", views.tags_view),
    path("api/guidelines/vocabulary", views.vocabulary_view),
    path("api/guidelines/rubrics/parse", views.parse_rubric_view),
    path("api/guidelines/for-score/<int:score_id>", views.for_score_view),
    path("api/guidelines/<int:guideline_id>", views.guideline_view),
    path("api/scores/<int:score_id>/tags", views.score_tags_view),
]
