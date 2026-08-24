options(echo=TRUE) # if you want see commands in output file
args <- commandArgs(trailingOnly = TRUE)
print(args)
if ( length(args) > 0){
    packages_file = args[1]
} else {
    packages_file = 'packages.txt'
}
f = read.csv(packages_file, header=FALSE, stringsAsFactors = FALSE)

# Install to the current user's R library when no writable library has already
# been configured.  This lets the script run without administrator privileges.
user_lib <- Sys.getenv("R_LIBS_USER")
if (!nzchar(user_lib)) {
    user_lib <- file.path(path.expand("~"), "R", paste0(
        R.version$platform, "-library",
        paste(R.version$major, strsplit(R.version$minor, "\\.")[[1]][1], sep = ".")
    ))
}
if (!dir.exists(user_lib)) {
    dir.create(user_lib, recursive = TRUE)
}

z = install.packages(f[,1], repos='https://cran.rstudio.com', lib = user_lib, Ncpus = 4)
