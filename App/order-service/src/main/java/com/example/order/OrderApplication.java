package com.example.order;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

@SpringBootApplication
@RestController
public class OrderApplication {

    private final RestTemplate restTemplate = new RestTemplate();
    
    @GetMapping("/")
    public String home() {
        return "{\"service\":\"order-service\",\"status\":\"running\"}";
    }
    
    @GetMapping("/orders")
    public String getOrders() {
        String userServiceUrl = System.getenv().getOrDefault("USER_SERVICE_URL", "http://user-service:8080");
        String productServiceUrl = System.getenv().getOrDefault("PRODUCT_SERVICE_URL", "http://product-service:8080");
        
        String users = restTemplate.getForObject(userServiceUrl + "/users", String.class);
        String products = restTemplate.getForObject(productServiceUrl + "/products", String.class);

        return "{\"orders\":[{\"id\":1,\"userId\":1,\"productId\":1,\"amount\":99.99}],\"users\":" + (users != null ? users : "[]") + ",\"products\":" + (products != null ? products : "[]") + "}";
    }
    
    public static void main(String[] args) {
        SpringApplication.run(OrderApplication.class, args);
    }
}
