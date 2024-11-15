public class BusinessException : Exception
{
    public string Code { get; }

    public BusinessException(string message, string code = "BUSINESS_ERROR")
        : base(message)
    {
        Code = code;
    }
}