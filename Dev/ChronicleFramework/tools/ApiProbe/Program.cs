using System.Reflection;
using System.Runtime.Loader;

if (args.Length < 2)
{
    Console.Error.WriteLine("Usage: ApiProbe <assembly path> <full type name> [member name] | ApiProbe --search <assembly path> <text>");
    return 2;
}

var searchMode = args[0] == "--search";
var assemblyArgumentIndex = searchMode ? 1 : 0;
var assemblyPath = Path.GetFullPath(args[assemblyArgumentIndex]);
var assemblyDirectory = Path.GetDirectoryName(assemblyPath)!;
var resolverDirectories = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
{
    assemblyDirectory
};
var possibleGameBinaryDirectory = Path.GetFullPath(Path.Combine(
    assemblyDirectory,
    "..", "..", "..", "..", "bin", "Win64_Shipping_Client"));
if (Directory.Exists(possibleGameBinaryDirectory))
{
    resolverDirectories.Add(possibleGameBinaryDirectory);
}
AssemblyLoadContext.Default.Resolving += (_, assemblyName) =>
{
    foreach (var resolverDirectory in resolverDirectories)
    {
        var candidate = Path.Combine(resolverDirectory, assemblyName.Name + ".dll");
        if (File.Exists(candidate))
        {
            return AssemblyLoadContext.Default.LoadFromAssemblyPath(candidate);
        }
    }
    return null;
};

var assembly = AssemblyLoadContext.Default.LoadFromAssemblyPath(assemblyPath);
if (searchMode)
{
    if (args.Length < 3)
    {
        Console.Error.WriteLine("Search mode requires text to search for.");
        return 2;
    }

    var searchText = args[2];
    Type[] types;
    try
    {
        types = assembly.GetTypes();
    }
    catch (ReflectionTypeLoadException exception)
    {
        types = exception.Types.Where(type => type is not null).Cast<Type>().ToArray();
        Console.Error.WriteLine($"Partial type load: {exception.LoaderExceptions.Length} unresolved dependencies.");
    }

    foreach (var type in types.OrderBy(type => type.FullName))
    {
        var typeMatches = type.FullName?.Contains(searchText, StringComparison.OrdinalIgnoreCase) == true;
        var methodMatches = type
            .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
            .Where(method => method.Name.Contains(searchText, StringComparison.OrdinalIgnoreCase));

        if (typeMatches || methodMatches.Any())
        {
            Console.WriteLine(type.FullName);
            foreach (var method in methodMatches)
            {
                Console.WriteLine($"  {method.Name}");
            }
        }
    }

    return 0;
}

var targetType = assembly.GetType(args[1], throwOnError: false);
if (targetType is null)
{
    Console.Error.WriteLine($"Type not found: {args[1]}");
    return 3;
}

var methodName = args.Length > 2 ? args[2] : null;
var methods = targetType
    .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
    .Where(method => methodName is null || method.Name == methodName || method.Name == $"get_{methodName}")
    .OrderBy(method => method.Name)
    .ThenBy(method => method.GetParameters().Length);

Console.WriteLine($"{targetType.FullName} from {Path.GetFileName(assemblyPath)}");
foreach (var method in methods)
{
    var access = method.IsPublic ? "public" : method.IsFamily ? "protected" : method.IsPrivate ? "private" : "internal";
    var modifiers = string.Join(' ', new[]
    {
        method.IsStatic ? "static" : string.Empty,
        method.IsAbstract ? "abstract" : string.Empty,
        method.IsVirtual && !method.IsAbstract ? "virtual" : string.Empty
    }.Where(value => value.Length > 0));
    var parameters = string.Join(", ", method.GetParameters().Select(parameter => $"{parameter.ParameterType.FullName} {parameter.Name}"));
    Console.WriteLine($"{access} {modifiers} {method.ReturnType.FullName} {method.Name}({parameters})".Replace("  ", " "));
}

var properties = targetType
    .GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
    .Where(property => methodName is null || property.Name == methodName)
    .OrderBy(property => property.Name);

foreach (var property in properties)
{
    Console.WriteLine($"property {property.PropertyType.FullName} {property.Name}");
}

return 0;
