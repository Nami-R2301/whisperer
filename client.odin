package whisper;

import "core:fmt";
import sys "core:sys/posix"
import os "core:os";
import mem "core:mem";
import libc "core:c/libc";

sig_int_handler :: proc "c" (sig: sys.Signal) {
	libc.printf("Do you really want to exit? [y\\n]");

	response: u8;
	libc.scanf("%c", &response);

	if response == 'Y' || response == 'y' {
		libc.exit(0);
	}
}

main :: proc () {
	assert(len(os.args) == 2, "Need to pass in an IPV4 address to connect to\n");
	fmt.println("Initializing socket...");

	socket : sys.FD = sys.socket(sys.AF.INET, sys.Sock.STREAM, sys.Protocol.IP);
	last_error : sys.Errno = sys.get_errno();
	if last_error != sys.Errno.NONE {
		fmt.printfln("Error encountered when attempting to init socket: %s", sys.strerror(last_error));
		panic("Cannot init socket\n");
	}

	defer {
		fmt.println("Shutting down client socket...");
		sys.shutdown(socket, sys.Shut.RDWR);  // Flush the read and write pipe before closing socket.
		sys.close(socket);
	}

	sin_port := cast(u16be) 9999; // Convert port to big-endian (network byte order).
	sin_addr := sys.in_addr {};
	ipv4_addr := os.args[1];
	cstr: [16]u8;
	mem.zero(&cstr, 16);  // Make sure to sanitize buffer.

	for i := 0; i < len(ipv4_addr); i += 1 {
		cstr[i] = ipv4_addr[i];
	}

	pton_result := sys.inet_pton(sys.AF.INET, cstring(rawptr(&cstr)), &sin_addr, size_of(sin_addr));
	if pton_result != sys.pton_result.SUCCESS {
		fmt.printfln("Error encountered when attempting to convert IPV4 address to big endian: %s [%d]",
		pton_result);
		return;
	}

	sock_addr_in := sys.sockaddr_in {sys.sa_family_t.INET, sin_port, sin_addr, {0,0,0,0,0,0,0,0}};

	fmt.printfln("Connecting to socket at address %s...", os.args[1]);
	result := sys.connect(socket, cast(^sys.sockaddr) &sock_addr_in, size_of(sys.sockaddr_in));
	if result != sys.result.OK {
		fmt.printfln("Error encountered when attempting to connect to server: %s [%d]",
			sys.strerror(sys.get_errno()), sys.get_errno());
		return;
	}
	fmt.println("Connected");
	response_msg: [1024]u8;
	mem.zero(&response_msg, 1024);  // Sanitize output.

	msg : string = "PING";
	bytes_sent := sys.send(socket, raw_data(msg), len(msg), {});
	if bytes_sent <= 0 {
		fmt.printfln("Error encountered when attempting to send welcome msg: %s [%d]",
		sys.strerror(sys.get_errno()), sys.get_errno());
		return;
	}

	bytes_received := sys.recv(socket, &response_msg, 1024, {});
	if bytes_received < 0 {
		fmt.printfln("Error encountered when attempting to get greeting msg: %s [%d]",
		sys.strerror(sys.get_errno()), sys.get_errno());
		return;
	}
	response_str : string = string(response_msg[:bytes_received]);
	fmt.printfln("[%s]:\t%s (%d bytes)", ipv4_addr, response_str, bytes_received);

	// Handle CTRL-C.
	sys.signal(sys.Signal.SIGINT, sig_int_handler);

	for true {
		data : [1024]byte;
		mem.zero(&data, 1024);
		bytes_read, error := os.read(os.stdout, data[:]);

		// EOF.
		if bytes_read == 0 {
			return;
		}
		if error == os.ERROR_EOF || bytes_read < 0 {
			fmt.printfln("Error encountered when attempting to read input: %s [%d]",
			sys.strerror(sys.get_errno()), sys.get_errno());
			return;
		}

		bytes_to_str : string = string(data[:bytes_read]);
		bytes_sent = sys.send(socket, raw_data(bytes_to_str), len(bytes_to_str), {});
		if bytes_sent <= 0 {
			fmt.printfln("Error encountered when attempting to send welcome msg: %s [%d]",
			sys.strerror(sys.get_errno()), sys.get_errno());
		}

		response : [1024]byte;
		mem.zero(&response, 1024);

		bytes_read = sys.recv(socket, &response, size_of(response), {});
		if bytes_read <= 0 {
			fmt.println("Server timeout or disconnected");
			return;
		}

		response_to_str := string(response[:bytes_read]);
		fmt.printfln("[%s]:\t%s", ipv4_addr, response_to_str);
	}
}
