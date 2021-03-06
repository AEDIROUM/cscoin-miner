using GLib;

extern void init_genrand64 (uint64 seed);
extern uint64 genrand64_int64 ();

int main (string[] args)
{
	Test.init (ref args);

	Test.add_func ("/sorted_list", () => {
		var hash_prefix = "768e";
		var last_solution_hash = Checksum.compute_for_string (ChecksumType.SHA256, "test");
		var nonce = CSCoin.solve_challenge (0, CSCoin.ChallengeType.SORTED_LIST, last_solution_hash, hash_prefix, CSCoin.ChallengeParameters () {nb_elements = 20});

		var seed_str = Checksum.compute_for_string (ChecksumType.SHA256, last_solution_hash + nonce);
		var seed = uint64.parse ("0x" + seed_str[14:16] + seed_str[12:14] + seed_str[10:12] + seed_str[8:10] + seed_str[6:8] + seed_str[4:6] + seed_str[2:4] + seed_str[0:2]);

		init_genrand64 (seed);

		var numbers = new SList<uint64?> ();
		for (var i = 0; i < 20; i++) {
			numbers.append (genrand64_int64 ());
		}

		numbers.sort ((a, b) => a < b ? -1 : 1);

		var checksum = new Checksum (ChecksumType.SHA256);

		foreach (var num in numbers) {
			var num_str = num.to_string ();
			checksum.update (num_str.data, num_str.length);
		}

		assert (checksum.get_string ().has_prefix (hash_prefix));
	});

	Test.add_func ("/reverse_sorted_list", () => {
		var hash_prefix = "768e";
		var last_solution_hash = Checksum.compute_for_string (ChecksumType.SHA256, "test");
		var nonce = CSCoin.solve_challenge (0, CSCoin.ChallengeType.REVERSE_SORTED_LIST, last_solution_hash, hash_prefix, CSCoin.ChallengeParameters () {nb_elements = 20});

		var seed_str = Checksum.compute_for_string (ChecksumType.SHA256, last_solution_hash + nonce);
		var seed = uint64.parse ("0x" + seed_str[14:16] + seed_str[12:14] + seed_str[10:12] + seed_str[8:10] + seed_str[6:8] + seed_str[4:6] + seed_str[2:4] + seed_str[0:2]);

		init_genrand64 (seed);

		var numbers = new SList<uint64?> ();
		for (var i = 0; i < 20; i++) {
			numbers.append (genrand64_int64 ());
		}

		numbers.sort ((a, b) => a > b ? -1 : 1);

		var checksum = new Checksum (ChecksumType.SHA256);

		foreach (var num in numbers) {
			var num_str = num.to_string ();
			checksum.update (num_str.data, num_str.length);
		}

		assert (checksum.get_string ().has_prefix (hash_prefix));
	});

	Test.add_func ("/shortest_path", () => {
		var hash_prefix = "768e";
		var last_solution_hash = Checksum.compute_for_string (ChecksumType.SHA256, "test");
		var nonce = CSCoin.solve_challenge (0, CSCoin.ChallengeType.SHORTEST_PATH, last_solution_hash, hash_prefix, CSCoin.ChallengeParameters () {nb_elements = 20});
	});

	return Test.run ();
}
