from django.urls import path

from . import views

urlpatterns = [
    path("api/auth/register", views.register),
    path("api/auth/login", views.login),
    path("api/auth/logout", views.logout),
    path("api/auth/me", views.me),
    path("api/auth/export", views.export),
    path("api/auth/account", views.delete_account),
]
