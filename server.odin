package whisper;

import "core:fmt";
import sys "core:sys/posix"
import os "core:os";
import mem "core:mem"

main :: proc() {
    assert(len(os.args) == 2, "Need to pass in an IPV4 address to connect to\n");
    fmt.println("Initializing socket...");

    socket : sys.FD = sys.socket(sys.AF.INET, sys.Sock.STREAM, sys.Protocol.IP);
    last_error : sys.Errno = sys.get_errno();
    if last_error != sys.Errno.NONE {
        fmt.printfln("Error encountered when attempting to init socket: %s", sys.strerror(last_error));
        panic("Cannot init socket\n");
    }

    defer {
        fmt.println("Shutting down server socket...");
        sys.shutdown(socket, sys.Shut.RDWR);
        sys.close(socket);
    }

    sin_port := cast(u16be) 9999; // Convert port to big-endian (network byte order).
    sin_addr := sys.in_addr {};
    ipv4_addr := os.args[1];
    cstr: [16]u8;
    mem.set(&cstr, 0, 16);  // Make sure to sanitize buffer.

    for i := 0; i < len(ipv4_addr); i += 1 {
        cstr[i] = ipv4_addr[i];
    }

    // Add this code to enable address reuse
    option_value: i32 = 1;
    if sys.setsockopt(socket, sys.SOL_SOCKET, sys.Sock_Option.REUSEADDR, &option_value, size_of(i32)) != sys.result.OK {
        fmt.printfln("Error setting SO_REUSEADDR: %s", sys.strerror(sys.get_errno()));
        return;
    }

    pton_result := sys.inet_pton(sys.AF.INET, cstring(rawptr(&cstr)), &sin_addr, size_of(sin_addr));
    if pton_result != sys.pton_result.SUCCESS {
        fmt.printfln("Error encountered when attempting to convert IPV4 address to big endian: %s [%d]",
        pton_result);
        return;
    }

    sock_addr_in := sys.sockaddr_in {sys.sa_family_t.INET, sin_port, sin_addr, {0,0,0,0,0,0,0,0}};

    result := sys.bind(socket, cast(^sys.sockaddr) &sock_addr_in, size_of(sys.sockaddr_in));
    if result != sys.result.OK {
        fmt.printfln("Error encountered when attempting to bind the server: %s [%d]",
        sys.strerror(sys.get_errno()), sys.get_errno());
        return;
    }

    res := sys.listen(socket, 5);
    if res != sys.result.OK {
        fmt.printfln("Error encountered when attempting to listen to the socket: %s [%d]",
        sys.strerror(sys.get_errno()), sys.get_errno());
        panic("Cannot listen to socket");
    }
    fmt.printfln("Server is listening on %s:9999", ipv4_addr);

    client_fd := initial_connection(socket, ipv4_addr);

    for true {
        response_msg: [1024]u8;
        mem.zero(&response_msg, 1024);  // Sanitize output.

        bytes_received := sys.recv(client_fd, &response_msg, 1024, {});
        if bytes_received == 0 {
            // Finished reading.
            fmt.printfln("Client [%d]:\tDisconnected", client_fd);
            client_fd = initial_connection(socket, ipv4_addr);
            continue;
        }

        if bytes_received < 0 {
            fmt.printfln("Error encountered when attempting to receive message: %s [%d]",
            sys.strerror(sys.get_errno()), sys.get_errno());
            continue;
        }

        // Remove newline.
        response_str : string = string(response_msg[:bytes_received - 1]);
        fmt.printfln("Client [%d]:\t%s (%d bytes)", client_fd, response_str, bytes_received);

        if sys.send(client_fd, raw_data(response_str), len(response_str), {}) <= 0 {
            fmt.printfln("Error encountered when attempting to send message: %s [%d]",
            sys.strerror(sys.get_errno()), sys.get_errno());
            continue;
        }
    }
}

initial_connection :: proc(socket: sys.FD, ipv4_addr: string) -> sys.FD {
    client_sock_addr : sys.sockaddr_in = {};
    size_client_socket : sys.socklen_t = size_of(client_sock_addr);

    client_fd := sys.accept(socket, cast(^sys.sockaddr) &client_sock_addr, &size_client_socket);

    if client_fd == -1 {
        fmt.printfln("Error encountered when attempting to accept the incoming connection: %s [%d]",
        sys.strerror(sys.get_errno()), sys.get_errno());
        panic("Cannot accept incoming connection");
    }
    fmt.printfln("Client [%d]:\tConnected", client_fd);

    response_msg: [1024]u8;
    mem.zero(&response_msg, 1024);  // Sanitize output.

    bytes_received := sys.recv(client_fd, &response_msg, 1024, {});
    if bytes_received == 0 {
        return client_fd;  // Finished reading.
    }
    if bytes_received < 0 {
        fmt.printfln("Error encountered when attempting to get greeting msg: %s [%d]",
        sys.strerror(sys.get_errno()), sys.get_errno());
        panic("Cannot fetch welcome message");
    }

    response_str : string = string(response_msg[:bytes_received]);
    fmt.printfln("Client [%d]:\t%s (%d bytes)", client_fd, response_str, bytes_received);

    msg := "PONG";
    if sys.send(client_fd, raw_data(msg), len(msg), {}) <= 0 {
        fmt.printfln("Error encountered when attempting to send welcome msg: %s [%d]",
        sys.strerror(sys.get_errno()), sys.get_errno());
        panic("Cannot send welcome message back");
    }

    return client_fd;
}

