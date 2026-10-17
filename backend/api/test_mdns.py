from unittest import mock

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


class StartTests(SimpleTestCase):
    """Starting a second server (or restarting one whose old announcement hasn't expired) must not crash Django."""

    def setUp(self):
        import api.mdns as mdns

        self.mdns = mdns
        mdns._zeroconf = None
        self.addCleanup(setattr, mdns, "_zeroconf", None)

    def test_a_taken_service_name_is_renamed_instead_of_raising(self):
        with mock.patch.object(self.mdns, "Zeroconf") as zeroconf, mock.patch.object(self.mdns, "_local_ip", return_value="192.0.2.7"), mock.patch.object(self.mdns.atexit, "register"):
            self.mdns.start(8000)

        register = zeroconf.return_value.register_service
        register.assert_called_once()
        # Without allow_name_change, zeroconf raises NonUniqueNameException when the name is already announced.
        self.assertIs(register.call_args.kwargs.get("allow_name_change"), True)
