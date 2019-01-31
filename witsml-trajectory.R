library(xml2)
library(data.table)
library(dplyr)
library(tibble)


get_trajectory_attributes_df <- function(xml_dat) {
    xml_find_first(xml_dat, "//trajectory") %>% 
        xml_attrs() %>% 
        t() %>% 
        data.frame(stringsAsFactors = FALSE)    
}

get_trajectory_metadata <- function(xml_dat) {
    # get all the trajectory variables, with and without descendants
    trajectory_children <- xml_name(xml_children(xml_find_first(xml_dat, "//trajectory")))
    
    # get only those variables without descendants. hnc: have no children
    traj_hnc_names <- names(have_no_children(xml_dat, "trajectory"))
    traj_hnc_idx <- which(trajectory_children %in% traj_hnc_names)
    
    traj_hnc <- xml_text(xml_children(xml_find_first(xml_dat, "//trajectory")))[traj_hnc_idx]
    names(traj_hnc) <- traj_hnc_names
    
    # dataframe and datatable
    data.frame(t(traj_hnc), stringsAsFactors = FALSE)
}


# uid dataframe
get_trajectoryStation_uid_df <- function(xml_dat) {
    # get values for uid attribute of trajectoryStation
    # these are the well ids
    tS.uid <- xml_dat %>% 
        xml_find_all("//trajectoryStation") %>% 
        xml_attr("uid")
    as_tibble(data.frame(uid = tS.uid, stringsAsFactors = FALSE))
}

# measurements dataframe
get_trajectoryStation_meas_df <- function(xml_dat) {
    num_trajectoryStation <- get_numrows_parent_node(xml_dat, "trajectoryStation", 
                                                     attribute = "uid")
    tS.trajectoryStation_df <- nodes_as_df(xml_dat, "trajectoryStation", 
                                           num_trajectoryStation)
    as_tibble(tS.trajectoryStation_df)    
}

# commonData
get_trajectoryStation_cData_df <- function(xml_dat, nrows) {
    tS.cD_df <- nodes_as_df(xml_dat, node = "trajectoryStation/commonData", 
                            max_obs = nrows)
    as_tibble(tS.cD_df)    
}

# corUsed
get_trajectoryStation_cUsed_df <- function(xml_dat, nrows) {
    tS.cU_df <- nodes_as_df(xml_dat, node = "trajectoryStation/corUsed", 
                            max_obs = nrows)
    as_tibble(tS.cU_df)
}


make_id_to_trajectoryStation_dt <- function(tS_df) {
    # create a new column id for relationship to another table
    id <- tS_df[1, "uid"]
    sub_id <- gsub(pattern = "_.*$", replacement = "", x = id)
    tS_df <- tS_df %>% 
        mutate(id = sub_id) %>% 
        select(id, everything()) %>% 
        as_tibble()
    data.table(tS_df)
}

make_trajectory_table <- function(t_dt, tS_dt) {
    setkey(t_dt, "uid")
    setkey(tS_dt, "id")
    
    # inner join
    result <- t_dt[tS_dt, nomatch=0]
    result %>% 
        as_tibble()
}


#' Get the names of variables under a node
#'
#' @param xml_dat a XML document
#' @param node a node of the form parent_node\child_node
#'
#' @return a character vector with the names of the variables
#' @export
#'
#' @examples
get_variables_under_node <- function(xml_dat, node) {
    xpath <- paste("//", node)
    xml_find_all(xml_dat, xpath) %>% 
        xml_children() %>% 
        xml_name() %>% 
        unique()
}


#' How many children does a parent node have
#' 
#' Returns a character vector with the name of the vector and the node count
#' @param xml_dat a XML document
#' @param node a node of the form parent_node\child_node
#'
how_many_children <- function(xml_dat, node) {
    vars_vector <- vector("integer")
    var_names <- get_variables_under_node(xml_dat, node)
    i <- 1
    for (var in var_names) {
        xpath <- paste("//", node, "/", var)  
        num_children <- max(xml_length(xml_find_all(xml_dat, xpath)))
        vars_vector[i] <- num_children
        names(vars_vector)[i] <- var
        # cat(i, var, vars_vector[i], "\n")
        i <- i + 1
    } 
    vars_vector
}


#' Get a vector of those nodes that have children and their count
#'
#' @param xml_dat 
#' @param node 
#'
have_children <- function(xml_dat, node) {
    how_many <- how_many_children(xml_dat, node)
    how_many[how_many > 0]
}

#' Get a vector of those nodes that do not have children and their zero count.
#'
#' @param xml_dat 
#' @param node 
#'
have_no_children <- function(xml_dat, node) {
    how_many <- how_many_children(xml_dat, node)
    how_many[how_many == 0]
}


# get the number of rows for a parent node
#' Get the number of rows for a parent node.
#'
#' @param xml_dat the xml document
#' @param parent_node a node without the two forward slashes
#' @param attribute the attribute of the node if available
#'
#' @return
#' @export
#'
#' @examples
get_numrows_parent_node <- function(xml_dat, parent_node, attribute) {
    # TODO: validate if the node has an attribute
    xml_dat %>% 
        xml_find_all(paste("//", parent_node)) %>%
        xml_attr("uid") %>%
        length()
}


#' Converts children of a node and their values to a dataframe.
#' Receives a node (do not add '//'), creates a vector with the variables under
#' the node, iterates through each of the variables, fills uneven rows with NAs.
#' It will skip a child node that contains children.
#'
#' @param xml_dat a xml document
#' @param node a node of the form "trajectoryStation/dTimStn". No need to add "//"
#' @param max_obs 
nodes_as_df <- function(xml_dat, node, max_obs) {
    li_vars <- vector("list")             # vector of list
    var_names <- get_variables_under_node(xml_dat, node)
    for (var in var_names) {              # iterate through all the variables
        xpath <- paste("//", node, "/", var)  # form the xpath
        num_children <- max(xml_length(xml_find_all(xml_dat, xpath)))
        if (num_children == 0) {  # skip if the node has children
            value_xpath <- xml_text(xml_find_all(xml_dat, xpath)) # get all the values
            vx <- value_xpath                                  # make it a shorter name
            # if the variables are all not present, add NA. max=25
            # cat(var, max_obs, length(vx), "\n")
            if (length(vx) < max_obs) vx <- c(rep(NA, max_obs - length(vx)), vx)
            li_vars[[var]] <- vx
        }
    }
    as.data.frame(li_vars, stringsAsFactors = FALSE)
}


convert_witsml_to_df <- function(witsml_file) {
    x <- read_xml(witsml_file)
    
    
    x <- xml_ns_strip(x)
    
    # create dataframe for trajectory
    t_attr <- get_trajectory_attributes_df(x)
    t_meta <- get_trajectory_metadata(x)
    trajectory_dt <- data.table(cbind(t_attr, t_meta))
    
    # create dataframe for trajectoryStation
    num_tS <- get_numrows_parent_node(x, "trajectoryStation", attribute = "uid")
    # build complete dataframe for trajectoryStation
    tS.uid_df <- get_trajectoryStation_uid_df(x)
    tS.measurements_df <- get_trajectoryStation_meas_df(x)
    tS.corUsed <- get_trajectoryStation_cUsed_df(x, num_tS)
    tS.commonData_df <- get_trajectoryStation_cData_df(x, num_tS)
    # bind all the columns
    trajectoryStation_df <- as_tibble(cbind(tS.uid_df,
                                            tS.measurements_df, 
                                            tS.corUsed, 
                                            tS.commonData_df)
    )
    trajectoryStation_dt <- make_id_to_trajectoryStation_dt(trajectoryStation_df)
    
    # final datatable
    make_trajectory_table(trajectory_dt, trajectoryStation_dt)
}
