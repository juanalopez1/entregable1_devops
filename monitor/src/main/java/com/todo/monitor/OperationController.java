package com.todo.monitor;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.validation.Valid;
import java.util.Set;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/operations")
public class OperationController {

    private static final Set<String> OPERATIONS = Set.of("create", "complete", "delete");
    private static final Set<String> VERSIONS = Set.of("blue", "green");
    private static final Set<String> PRIORITIES = Set.of("none", "baja", "media", "alta");

    private final MeterRegistry meterRegistry;

    public OperationController(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }

    @PostMapping
    public ResponseEntity<Void> record(@Valid @RequestBody OperationRequest request) {
        String operation = normalize(request.operation());
        String version = normalize(request.version());
        String priority = request.priority() == null || request.priority().isBlank()
                ? "none"
                : normalize(request.priority());

        if (!OPERATIONS.contains(operation) || !VERSIONS.contains(version) || !PRIORITIES.contains(priority)) {
            return ResponseEntity.badRequest().build();
        }

        Counter.builder("todo.operations")
                .description("Operaciones de tareas reportadas por la aplicacion Flask")
                .tag("operation", operation)
                .tag("resource", "task")
                .tag("version", version)
                .tag("priority", priority)
                .register(meterRegistry)
                .increment();

        return ResponseEntity.accepted().build();
    }

    private static String normalize(String value) {
        return value.trim().toLowerCase();
    }
}
