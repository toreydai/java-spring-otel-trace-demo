package com.example.user;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.*;

@SpringBootApplication
@RestController
public class UserApplication {
    
    @GetMapping("/")
    public String home() {
        return "{\"service\":\"user-service\",\"status\":\"running\"}";
    }
    
    @GetMapping("/users")
    public String getUsers() {
        return "{\"users\":[{\"id\":1,\"name\":\"Alice\",\"email\":\"alice@example.com\"},{\"id\":2,\"name\":\"Bob\",\"email\":\"bob@example.com\"}]}";
    }
    
    @GetMapping("/users/{id}")
    public String getUser(@PathVariable String id) {
        return "{\"id\":" + id + ",\"name\":\"User" + id + "\",\"email\":\"user" + id + "@example.com\"}";
    }
    
    public static void main(String[] args) {
        SpringApplication.run(UserApplication.class, args);
    }
}
