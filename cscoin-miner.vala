using GLib;

[CCode (lower_case_cprefix = "cscoin_")]
namespace CSCoin
{
	string generate_command (string command_name, ...)
	{
		var builder = new Json.Builder ();

		builder.begin_object ();
		builder.set_member_name ("command");
		builder.add_string_value (command_name);

		builder.set_member_name ("args");
		builder.begin_object ();
		var list = va_list ();
		unowned string? key, val;
		for (key = list.arg<string?> (), val = list.arg<string?> ();
		     key != null && val != null;
		     key = list.arg<string?> (), val = list.arg<string?> ())
		{
			builder.set_member_name (key.replace ("-", "_"));
			builder.add_string_value (val);
		}
		// TODO: add command arguments
		builder.end_object ();

		builder.end_object ();

		return Json.to_string (builder.get_root (), false);
	}

	string wallet_path;

	const OptionEntry[] options =
	{
		{"wallet", 'w', 0, OptionArg.FILENAME, ref wallet_path, "Path to the wallet if it exists, otherwise it will be created", "FILE"},
		{null}
	};

	int main (string[] args)
	{
		try
		{
			var parser = new OptionContext ();
			parser.add_main_entries (options, null);
			parser.parse (ref args);
		}
		catch (OptionError err)
		{
			return 1;
		}

		if (args.length < 2)
		{
			stderr.printf ("Usage: %s <url>\n", args[0]);
			return 1;
		}

		var wallet = new OpenSSL.RSA ();

		message ("Generating a random key pair...");
		var e = new OpenSSL.Bignum ();
		e.set_word (65537);
		wallet.generate_key_ex (1024, e);

		var wallet_id = Checksum.compute_for_string (ChecksumType.SHA256, wallet.d.bn2dec ());

		var ws_url = args[1];

		var ws_session = new Soup.Session ();
		var ws_message = new Soup.Message ("GET", ws_url);

		ws_session.websocket_connect_async.begin (ws_message, null, null, null, (obj, res) => {
			Soup.WebsocketConnection ws;
			try
			{
				ws = ws_session.websocket_connect_async.end (res);
			}
			catch (Error err)
			{
				error (err.message);
			}

			var challenge_executor = new ThreadPool<Challenge>.with_owned_data ((challenge) => {
				message ("Received challenge #%lld: challenge-name: %s, last-solution-hash: %s, hash-prefix: %s.",
				         challenge.challenge_id,
				         challenge.challenge_type.to_string (),
				         challenge.last_solution_hash,
				         challenge.hash_prefix);

				var started = get_monotonic_time ();

				string nonce;
				try
				{
					nonce = solve_challenge (challenge.challenge_id,
					                         challenge.challenge_type,
					                         challenge.last_solution_hash,
					                         challenge.hash_prefix,
					                         challenge.parameters,
					                         challenge.cancellable);
				}
				catch (Error err)
				{
					critical ("%s (%s, %d)", err.message, err.domain.to_string (), err.code);
					return;
				}

				message ("Solved challenge #%lld in %lldms (%lds was given) with nonce '%s'.",
				         challenge.challenge_id,
				         (get_monotonic_time () - started) / 1000,
				         challenge.time_left,
				         nonce);

				message ("Submitting nonce '%s' for challenge #%lld to authority...", nonce, challenge.challenge_id);
				ws.send_text (generate_command ("submission", wallet_id: wallet_id, nonce: nonce.to_string ()));
			}, 1, true);

			Cancellable? current_challenge_cancellable = null;

			ws.message.connect ((type, payload) => {
				var response = Json.from_string ((string) payload.get_data ()).get_object ();

				if (response.has_member ("challenge_id"))
				{
					/* cancel any running challenge */
					current_challenge_cancellable.cancel ();
					current_challenge_cancellable = new Cancellable ();

					var challenge = new Challenge.from_json_object (response, current_challenge_cancellable);

					try
					{
						challenge_executor.add (challenge);
					}
					catch (ThreadError err)
					{
						critical ("Could not enqueue the challenge #%lld: %s", challenge.challenge_id, err.message);
					}
				}
				else if (response.has_member ("error"))
				{
					critical ("Received an error from CA: %s.", response.get_string_member ("error"));
				}
			});

			ws.closing.connect (() => {
				warning ("The connection is closing, cancelling any running challenges...");
				current_challenge_cancellable.cancel ();
			});

			ws.closed.connect (() => {
				message ("The connection is closed and will be reestablished in a few...");
			});

			ws.error.connect ((err) => {
				critical (err.message);
			});

			ws.send_text (generate_command ("get_current_challenge"));
		});

		new MainLoop ().run ();

		return 0;
	}
}
