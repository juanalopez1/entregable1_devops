package com.todo.monitor;

import jakarta.validation.constraints.NotBlank;

public record OperationRequest(
        @NotBlank String operation,
        String resource,
        @NotBlank String version,
        String priority
) {
}
