// SharedModels/Validators/CreateOrderValidator.cs
using FluentValidation;
using SharedModels.DTOs;

namespace SharedModels.Validators;

public class CreateOrderValidator : AbstractValidator<CreateOrderDto>
{
    public CreateOrderValidator()
    {
        RuleFor(x => x.ItemName)
            .NotEmpty()
            .MaximumLength(100);

        RuleFor(x => x.Quantity)
            .GreaterThan(0)
            .LessThanOrEqualTo(1000);
    }
}