package com.example.product;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.*;

@SpringBootApplication
@RestController
public class ProductApplication {
    
    @GetMapping("/")
    public String home() {
        return "{\"service\":\"product-service\",\"status\":\"running\"}";
    }
    
    @GetMapping("/products")
    public String getProducts() {
        return "{\"products\":[{\"id\":1,\"name\":\"Laptop\",\"price\":999.99},{\"id\":2,\"name\":\"Phone\",\"price\":599.99}]}";
    }
    
    @GetMapping("/products/{id}")
    public String getProduct(@PathVariable String id) {
        return "{\"id\":" + id + ",\"name\":\"Product" + id + "\",\"price\":99.99}";
    }
    
    public static void main(String[] args) {
        SpringApplication.run(ProductApplication.class, args);
    }
}
