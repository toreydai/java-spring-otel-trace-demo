package com.example.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import org.springframework.context.annotation.Bean;
import org.springframework.beans.factory.annotation.Autowired;

@SpringBootApplication
public class GatewayApplication {
    
    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
    
    public static void main(String[] args) {
        SpringApplication.run(GatewayApplication.class, args);
    }
}

@RestController
class GatewayController {
    
    @Autowired
    private RestTemplate restTemplate;
    
    @GetMapping("/")
    public String home() {
        return "{\"service\":\"gateway\",\"status\":\"running\"}";
    }
    
    @GetMapping("/api/orders")
    public String getOrders() {
        String orderServiceUrl = System.getenv().getOrDefault("ORDER_SERVICE_URL", "http://order-service:8080");
        return restTemplate.getForObject(orderServiceUrl + "/orders", String.class);
    }
    
    @GetMapping("/api/users")
    public String getUsers() {
        String userServiceUrl = System.getenv().getOrDefault("USER_SERVICE_URL", "http://user-service:8080");
        return restTemplate.getForObject(userServiceUrl + "/users", String.class);
    }
    
    @GetMapping("/api/products")
    public String getProducts() {
        String productServiceUrl = System.getenv().getOrDefault("PRODUCT_SERVICE_URL", "http://product-service:8080");
        return restTemplate.getForObject(productServiceUrl + "/products", String.class);
    }
}
