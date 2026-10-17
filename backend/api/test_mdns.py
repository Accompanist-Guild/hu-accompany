from django.test import SimpleTestCase

from api.mdns import server_name


class ServerNameTests(SimpleTestCase):
    """The name other devices use to find this machine, as announced over mDNS.

    A Bonjour host name must end in ".local." exactly once. macOS already reports its host name as
    "<name>.local", so adding ".local." again announced "<name>.local.local.", which resolves nowhere.
    """

    def test_a_plain_host_name_gets_local_added(self):
        self.assertEqual(server_name("build-box"), "build-box.local.")

    def test_a_mac_host_name_that_already_ends_in_local_is_not_doubled(self):
        self.assertEqual(server_name("Kingsleys-MacBook-Pro.local"), "Kingsleys-MacBook-Pro.local.")

    def test_the_suffix_check_ignores_case(self):
        self.assertEqual(server_name("Box.LOCAL"), "Box.local.")  # host names are case-insensitive

    def test_a_name_that_merely_contains_local_is_left_alone(self):
        self.assertEqual(server_name("localhost"), "localhost.local.")
        self.assertEqual(server_name("my.local.lab"), "my.local.lab.local.")
